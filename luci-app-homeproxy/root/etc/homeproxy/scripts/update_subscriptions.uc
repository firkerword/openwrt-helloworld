#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

'use strict';

import { open } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';

import { urldecode, urlencode, urldecode_params } from 'luci.http';
import { init_action } from 'luci.sys';

import {
	calcStringMD5, CURL, executeCommand, decodeBase64Str,
	isEmpty, parseURL, validation,
	HP_DIR, RUN_DIR
} from 'homeproxy';

/* UCI config start */
const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

const ucimain = 'config',
      ucinode = 'node',
      ucisubscription = 'subscription';

const allow_insecure = uci.get(uciconfig, ucisubscription, 'allow_insecure') || '0',
      filter_mode = uci.get(uciconfig, ucisubscription, 'filter_nodes') || 'disabled',
      filter_keywords = uci.get(uciconfig, ucisubscription, 'filter_keywords') || [],
      packet_encoding = uci.get(uciconfig, ucisubscription, 'packet_encoding') || 'xudp',
      subscription_urls = uci.get(uciconfig, ucisubscription, 'subscription_url') || [],
      via_proxy = uci.get(uciconfig, ucisubscription, 'update_via_proxy') || '0';

const routing_mode = uci.get(uciconfig, ucimain, 'routing_mode') || 'bypass_mainalnd_china';
let main_node, main_udp_node;
if (routing_mode !== 'custom') {
	main_node = uci.get(uciconfig, ucimain, 'main_node') || 'nil';
	main_udp_node = uci.get(uciconfig, ucimain, 'main_udp_node') || 'nil';
}
/* UCI config end */

/* String helper start */
function filter_check(name) {
	if (isEmpty(name) || filter_mode === 'disabled' || isEmpty(filter_keywords))
		return false;

	let ret = false;
	for (let i in filter_keywords) {
		const patten = regexp(i);
		if (match(name, patten))
			ret = true;
	}
	if (filter_mode === 'whitelist')
		ret = !ret;

	return ret;
}
/* String helper end */

/* Common var start */
const node_cache = {},
      node_result = [];

const ubus = connect();
const sing_features = ubus.call('luci.homeproxy', 'singbox_get_features', {}) || {};
/* Common var end */

/* Log */
system(`mkdir -p ${RUN_DIR}`);
function log(...args) {
	const logtime = trim(executeCommand('date "+%Y-%m-%d %H:%M:%S"').stdout);

	const logfile = open(`${RUN_DIR}/homeproxy.log`, 'a');
	logfile.write(`${logtime} [SUBSCRIBE] ${join(' ', args)}\n`);
	logfile.close();
}

function parse_uri(uri) {
	let config;

	if (type(uri) === 'object') {
		if (uri.nodetype === 'sip008') {
			/* https://shadowsocks.org/guide/sip008.html */
			config = {
				label: uri.remarks,
				type: 'shadowsocks',
				address: uri.server,
				port: uri.server_port,
				shadowsocks_encrypt_method: uri.method,
				password: uri.password,
				shadowsocks_plugin: uri.plugin,
				shadowsocks_plugin_opts: uri.plugin_opts
			};
		}
	} else if (type(uri) === 'string') {
		uri = split(trim(uri), '://');

		switch (uri[0]) {
		case 'hysteria':
			/* https://github.com/HyNetwork/hysteria/wiki/URI-Scheme */
			const hysteria_url = parseURL('http://' + uri[1]),
			      hysteria_params = hysteria_url.searchParams;

			if (!sing_features.with_quic || (hysteria_params.protocol && hysteria_params.protocol !== 'udp')) {
				log(sprintf('Skipping unsupported %s node: %s.', 'hysteria', urldecode(hysteria_url.hash) || hysteria_url.hostname));
				if (!sing_features.with_quic)
					log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

				return null;
			}

			config = {
				label: urldecode(hysteria_url.hash),
				type: 'hysteria',
				address: hysteria_url.hostname,
				port: hysteria_url.port,
				hysteria_protocol: hysteria_params.protocol || 'udp',
				hysteria_auth_type: hysteria_params.auth ? 'string' : null,
				hysteria_auth_payload: hysteria_params.auth,
				hysteria_obfs_password: hysteria_params.obfsParam,
				hysteria_down_mbps: hysteria_params.downmbps,
				hysteria_up_mbps: hysteria_params.upmbps,
				tls: '1',
				tls_insecure: (hysteria_params.insecure in ['true', '1']) ? '1' : '0',
				tls_sni: hysteria_params.peer,
				tls_alpn: hysteria_params.alpn
			};

			break;
		case 'ss':
			/* "Lovely" Shadowrocket format */
			const ss_suri = split(uri[1], '#');
			let ss_slabel = '';
			if (length(ss_suri) <= 2) {
				if (length(ss_suri) === 2)
					ss_slabel = '#' + urlencode(ss_suri[1]);
				if (decodeBase64Str(ss_suri[0]))
					uri[1] = decodeBase64Str(ss_suri[0]) + ss_slabel;
			}

			/* Legacy format is not supported, it should be never appeared in modern subscriptions */
			/* https://github.com/shadowsocks/shadowsocks-org/commit/78ca46cd6859a4e9475953ed34a2d301454f579e */

			/* SIP002 format https://shadowsocks.org/guide/sip002.html */
			const ss_url = parseURL('http://' + uri[1]);

			let ss_userinfo = {};
			if (ss_url.username && ss_url.password)
				/* User info encoded with URIComponent */
				ss_userinfo = [ss_url.username, urldecode(ss_url.password)];
			else if (ss_url.username)
				/* User info encoded with base64 */
				ss_userinfo = split(decodeBase64Str(urldecode(ss_url.username)), ':');

			let ss_plugin, ss_plugin_opts;
			if (ss_url.search && ss_url.searchParams.plugin) {
				const ss_plugin_info = split(ss_url.searchParams.plugin, ';');
				ss_plugin = ss_plugin_info[0];
				if (ss_plugin === 'simple-obfs')
					/* Fix non-standard plugin name */
					ss_plugin = 'obfs-local';
				ss_plugin_opts = slice(ss_plugin_info, 1) ? join(';', slice(ss_plugin_info, 1)) : null;
			}

			config = {
				label: ss_url.hash ? urldecode(ss_url.hash) : null,
				type: 'shadowsocks',
				address: ss_url.hostname,
				port: ss_url.port,
				shadowsocks_encrypt_method: ss_userinfo[0],
				password: ss_userinfo[1],
				shadowsocks_plugin: ss_plugin,
				shadowsocks_plugin_opts: ss_plugin_opts
			};

			break;
		case 'ssr':
			/* https://coderschool.cn/2498.html */
			uri = split(decodeBase64Str(uri[1]), '/');
			if (!uri)
				return null;

			const userinfo = split(uri[0], ':'),
			      ssr_params = urldecode_params(uri[1]);

			if (!sing_features.with_shadowsocksr) {
				log(sprintf('Skipping unsupported %s node: %s.', 'ShadowsocksR', decodeBase64Str(ssr_params.remarks) || userinfo[1]));
				log(sprintf('Please rebuild sing-box with %s support!', 'ShadowsocksR'));

				return null;
			}

			config = {
				label: decodeBase64Str(ssr_params.remarks),
				type: 'shadowsocksr',
				address: userinfo[0],
				port: userinfo[1],
				shadowsocksr_encrypt_method: userinfo[3],
				password: decodeBase64Str(userinfo[5]),
				shadowsocksr_protocol: userinfo[2],
				shadowsocksr_protocol_param: decodeBase64Str(ssr_params.protoparam),
				shadowsocksr_obfs: userinfo[4],
				shadowsocksr_obfs_param: decodeBase64Str(ssr_params.obfsparam)
			};

			break;
		case 'trojan':
			/* https://p4gefau1t.github.io/trojan-go/developer/url/ */
			const trojan_url = parseURL('http://' + uri[1]);

			config = {
				label: trojan_url.hash ? urldecode(trojan_url.hash) : null,
				type: 'trojan',
				address: trojan_url.hostname,
				port: trojan_url.port,
				password: urldecode(trojan_url.username),
				tls: '1',
				tls_sni: trojan_url.searchParams ? trojan_url.searchParams.sni : null
			};

			break;
		case 'vless':
			/* https://github.com/XTLS/Xray-core/discussions/716 */
			const vless_url = parseURL('http://' + uri[1]),
			      vless_params = vless_url.searchParams;

			/* Unsupported protocol */
			if (vless_params.type === 'kcp') {
				log(sprintf('Skipping sunsupported %s node: %s.', 'VLESS', urldecode(vless_url.hash) || vless_url.hostname));
				return null;
			} else if (vless_params.type === 'quic' && (vless_params.quicSecurity && vless_params.quicSecurity !== 'none' || !sing_features.with_quic)) {
				log(sprintf('Skipping sunsupported %s node: %s.', 'VLESS', urldecode(vless_url.hash) || vless_url.hostname));
				if (!sing_features.with_quic)
					log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

				return null;
			}

			config = {
				label: vless_url.hash ? urldecode(vless_url.hash) : null,
				type: 'vless',
				address: vless_url.hostname,
				port: vless_url.port,
				uuid: vless_url.username,
				transport: (vless_params.type !== 'tcp') ? vless_params.type : null,
				tls: vless_params.security ? '1' : '0',
				tls_sni: vless_params.sni,
				tls_alpn: vless_params.alpn ? split(urldecode(vless_params.alpn), ',') : null,
				tls_utls: sing_features.with_utls ? vless_params.fp : null
			};
			switch(vless_params.type) {
			case 'grpc':
				config.grpc_servicename = vless_params.serviceName;
				break;
			case 'http':
			case 'tcp':
				if (config.transport === 'http' || vless_params.headerType === 'http') {
					config.http_host = vless_params.host ? split(urldecode(vless_params.host), ',') : null;
					config.http_path = vless_params.path ? urldecode(vless_params.path) : null;
				}
				break;
			case 'ws':
				config.ws_host = (config.tls !== '1' && vless_params.host) ? urldecode(vless_params.host) : null;
				config.ws_path = vless_params.path ? urldecode(vless_params.path) : null;
				if (config.ws_path && match(config.ws_path, /\?ed=/)) {
					config.websocket_early_data_header = 'Sec-WebSocket-Protocol';
					config.websocket_early_data = split(config.ws_path, '?ed=')[1];
					config.ws_path = split(config.ws_path, '?ed=')[0];
				}
				break;
			}

			break;
		case 'vmess':
			/* "Lovely" shadowrocket format */
			if (match(uri, /&/)) {
				log(sprintf('Skipping unsupported %s format.', 'VMess'));
				return null;
			}

			/* https://github.com/2dust/v2rayN/wiki/%E5%88%86%E4%BA%AB%E9%93%BE%E6%8E%A5%E6%A0%BC%E5%BC%8F%E8%AF%B4%E6%98%8E(ver-2) */
			try {
				uri = json(decodeBase64Str(uri[1]));
			} catch(e) {
				log(sprintf('Skipping unsupported %s format.', 'VMess'));
				return null;
			}

			if (uri.v !== '2') {
				log(sprintf('Skipping unsupported %s format.', 'VMess'));
				return null;
			/* Unsupported protocol */
			} else if (uri.net === 'kcp') {
				log(sprintf('Skipping unsupported %s node: %s.', 'VMess', uri.ps || uri.add));
				return null;
			} else if (uri.net === 'quic' && ((uri.type && uri.type !== 'none') || uri.path || !sing_features.with_quic)) {
				log(sprintf('Skipping unsupported %s node: %s.', 'VMess', uri.ps || uri.add));
				if (!sing_features.with_quic)
					log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

				return null;
			}
			/*
			 * https://www.v2fly.org/config/protocols/vmess.html#vmess-md5-%E8%AE%A4%E8%AF%81%E4%BF%A1%E6%81%AF-%E6%B7%98%E6%B1%B0%E6%9C%BA%E5%88%B6
			 * else if (uri.aid && int(uri.aid) !== 0) {
			 * 	log(sprintf('Skipping unsupported %s node: %s.', 'VMess', uri.ps || uri.add));
			 * 	return null;
			 * }
			 */

			config = {
				label: uri.ps,
				type: 'vmess',
				address: uri.add,
				port: uri.port,
				uuid: uri.id,
				vmess_alterid: uri.aid,
				vmess_encrypt: uri.scy || 'auto',
				vmess_global_padding: '1',
				vmess_authenticated_length: '1',
				transport: (uri.net !== 'tcp') ? uri.net : null,
				tls: (uri.tls === 'tls') ? '1' : '0',
				tls_sni: uri.sni || uri.host,
				tls_alpn: uri.alpn ? split(uri.alpn, ',') : null
			};
			switch (uri.net) {
			case 'grpc':
				config.grpc_servicename = uri.path;
				break;
			case 'h2':
			case 'tcp':
				if (uri.net === 'h2' || uri.type === 'http') {
					config.transport = 'http';
					config.http_host = uri.host ? uri.host.split(',') : null;
					config.http_path = uri.path;
				}
				break;
			case 'ws':
				config.ws_host = (config.tls !== '1') ? uri.host : null;
				config.ws_path = uri.path;
				if (config.ws_path && match(config.ws_path, /\?ed=/)) {
					config.websocket_early_data_header = 'Sec-WebSocket-Protocol';
					config.websocket_early_data = split(config.ws_path, '?ed=')[1];
					config.ws_path = split(config.ws_path, '?ed=')[0];
				}
				break;
			}

			break;
		}
	}

	if (!isEmpty(config)) {
		if (config.address)
			config.address = replace(config.address, /\[|\]/g, '');

		if (validation('host', config.address) !== 0 || validation('port', config.port) !== 0) {
			log(sprintf('Skipping invalid %s node: %s.', config.type, config.label || 'NULL'));
			return null;
		} else if (!config.label)
			config.label = (validation('ip6addr', config.address) === 0 ?
				`[${config.address}]` : config.address) + ':' + config.port;
	}

	return config;
}

function main() {
	if (via_proxy !== '1') {
		log('Stopping service...');
		init_action('homeproxy', 'stop');
	}

	for (let url in subscription_urls) {
		const res = CURL(url);
		if (!res) {
			log(sprintf('Failed to fetch resources from %s.', url));
			continue;
		}

		const groupHash = calcStringMD5(url);
		node_cache[groupHash] = {};

		push(node_result, []);
		const subindex = length(node_result) - 1;

		let nodes;
		try {
			nodes = json(res).servers || json(res);

			/* Shadowsocks SIP008 format */
			if (nodes[0].server && nodes[0].method)
				map(nodes, (_, i) => nodes[i].nodetype = 'sip008');
		} catch(e) {
			nodes = decodeBase64Str(res);
			nodes = nodes ? split(trim(replace(nodes, / /g, '_')), '\n') : {};
		}

		let count = 0;
		for (let node in nodes) {
			let config;
			if (!isEmpty(node))
				config = parse_uri(node);
			if (isEmpty(config))
				continue;

			const label = config.label;
			config.label = null;
			const confHash = calcStringMD5(sprintf('%J', config)),
			      nameHash = calcStringMD5(label);
			config.label = label;

			if (filter_check(config.label))
				log(sprintf('Skipping blacklist node: %s.', config.label));
			else if (node_cache[groupHash][confHash] || node_cache[groupHash][nameHash])
				log(sprintf('Skipping duplicate node: %s.', config.label));
			else {
				if (config.tls === '1' && allow_insecure === '1')
					config.tls_insecure = '1';
				if (config.type in ['vless', 'vmess'])
					config.packet_encoding = packet_encoding;

				config.grouphash = groupHash;
				push(node_result[subindex], config);
				node_cache[groupHash][confHash] = config;
				node_cache[groupHash][nameHash] = config;

				count++;
			}
		}

		log(sprintf('Successfully fetched %s nodes of total %s from %s.', count, length(nodes), url));
	}

	if (isEmpty(node_result)) {
		log('Failed to update subscriptions: no valid node found.');

		if (via_proxy !== '1') {
			log('Starting service...');
			init_action('homeproxy', 'start');
		}

		return false;
	}

	let added = 0, removed = 0;
	uci.foreach(uciconfig, ucinode, (cfg) => {
		if (!cfg.grouphash)
			return null;

		if (!node_cache[cfg.grouphash] || !node_cache[cfg.grouphash][cfg['.name']]) {
			uci.delete(uciconfig, cfg['.name']);
			removed++;

			log(sprintf('Removing node: %s.', cfg.label || cfg['name']));
		} else {
			map(keys(node_cache[cfg.grouphash][cfg['.name']]), (v) => {
				uci.set(uciconfig, cfg['.name'], v, node_cache[cfg.grouphash][cfg['.name']][v]);
			});
			node_cache[cfg.grouphash][cfg['.name']].isExisting = true;
		}
	});
	for (let nodes in node_result)
		map(nodes, (node) => {
			if (node.isExisting)
				return null;

			const nameHash = calcStringMD5(node.label);
			uci.set(uciconfig, nameHash, 'node');
			map(keys(node), (v) => uci.set(uciconfig, nameHash, v, node[v]));

			added++;
			log(sprintf('Adding node: %s.', node.label));
		});
	uci.commit();

	let need_restart = (via_proxy !== '1');
	if (!isEmpty(main_node)) {
		const first_server = uci.get_first(uciconfig, ucinode);
		if (first_server) {
			if (!uci.get(uciconfig, main_node)) {
				uci.set(uciconfig, ucimain, 'main_node', first_server);
				uci.commit();
				need_restart = true;

				log('Main node is gone, switching to the first node.');
			}

			if (!isEmpty(main_udp_node) && main_udp_node !== 'same') {
				if (!uci.get(uciconfig, main_udp_node)) {
					uci.set(uciconfig, ucimain, 'main_udp_node', first_server);
					uci.commit();
					need_restart = true;

					log('Main UDP node is gone, switching to the first node.');
				}
			}
		} else {
			uci.set(uciconfig, ucimain, 'main_node', 'nil');
			uci.set(uciconfig, ucimain, 'main_udp_node', 'nil');
			uci.commit();
			need_restart = true;

			log('No available node, disable tproxy.');
		}
	}

	if (need_restart) {
		log('Restarting service...');
		init_action('homeproxy', 'stop');
		init_action('homeproxy', 'start');
	}

	log(sprintf('%s nodes added, %s removed.', added, removed));
	log('Successfully updated subscriptions.');
}

if (!isEmpty(subscription_urls))
	try {
		call(main);
	} catch(e) {
		log('[FATAL ERROR] An error occurred during updating subscriptions:');
		log(e);

		log('Restarting service...');
		init_action('homeproxy', 'stop');
		init_action('homeproxy', 'start');
	}
