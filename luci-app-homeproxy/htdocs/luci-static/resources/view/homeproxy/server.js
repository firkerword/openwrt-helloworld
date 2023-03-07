/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2023 ImmortalWrt.org
 */

'use strict';
'require form';
'require uci';
'require view';

'require homeproxy as hp';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('homeproxy'),
			hp.getBuiltinFeatures()
		]);
	},

	render: function(data) {
		var m, s, o;

		m = new form.Map('homeproxy', _('Edit servers'));

		s = m.section(form.NamedSection, 'server', 'homeproxy', _('Global settings'));

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.option(form.Flag, 'auto_firewall', _('Auto configure firewall'));
		o.default = o.enabled;

		s = m.section(form.GridSection, 'server');
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.modaltitle = L.bind(hp.loadModalTitle, this, _('Server'), _('Add a server'), data[0]);
		s.sectiontitle = L.bind(hp.loadDefaultLabel, this, data[0]);
		s.renderSectionAdd = L.bind(hp.renderSectionAdd, this, s);

		o = s.option(form.Value, 'label', _('Label'));
		o.load = L.bind(hp.loadDefaultLabel, this, data[0]);
		o.validate = L.bind(hp.validateUniqueValue, this, data[0], 'server', 'label');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = o.enabled;
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.ListValue, 'type', _('Type'));
		o.value('http', _('HTTP'));
		if (data[1].with_quic) {
			o.value('hysteria', _('Hysteria'));
			o.value('naive', _('NaïveProxy'));
		}
		o.value('shadowsocks', _('Shadowsocks'));
		o.value('socks', _('Socks'));
		o.value('trojan', _('Trojan'));
		o.value('vless', _('VLESS'));
		o.value('vmess', _('VMess'));
		o.rmempty = false;
		o.onchange = function(ev, section_id, value) {
			var tls_element = this.map.findElement('id', 'cbid.homeproxy.%s.tls'.format(section_id)).firstElementChild;
			if (value === 'hysteria') {
				var event = document.createEvent('HTMLEvents');
				event.initEvent('change', true, true);

				tls_element.checked = true;
				tls_element.dispatchEvent(event);
				tls_element.disabled = true;
			} else
				tls_element.disabled = null;
		}

		o = s.option(form.Value, 'port', _('Port'),
			_('The port must be unique.'));
		o.datatype = 'port';
		o.validate = L.bind(hp.validateUniqueValue, this, data[0], 'server', 'port');

		o = s.option(form.Value, 'username', _('Username'));
		o.depends('type', 'http');
		o.depends('type', 'naive');
		o.depends('type', 'socks');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'password', _('Password'));
		o.password = true;
		o.depends('type', 'http');
		o.depends('type', 'naive');
		o.depends('type', 'shadowsocks');
		o.depends('type', 'socks');
		o.depends('type', 'trojan');
		o.validate = function(section_id, value) {
			if (section_id) {
				var type = this.map.lookupOption('type', section_id)[0].formvalue(section_id);
				if (type === 'shadowsocks') {
					var encmode = this.map.lookupOption('shadowsocks_encrypt_method', section_id)[0].formvalue(section_id);
					if (encmode === 'none')
						return true;
					else if (encmode === '2022-blake3-aes-128-gcm')
						return hp.validateBase64Key(24, section_id, value);
					else if (['2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'].includes(encmode))
						return hp.validateBase64Key(44, section_id, value);
				}
				if (!value)
					return _('Expecting: %s').format(_('non-empty value'));
			}

			return true;
		}
		o.modalonly = true;

		/* Hysteria config start */
		o = s.option(form.ListValue, 'hysteria_protocol', _('Protocol'));
		o.value('udp');
		/* WeChat-Video / FakeTCP are unsupported by sing-box currently
		   o.value('wechat-video');
		   o.value('faketcp');
		*/
		o.default = 'udp';
		o.depends('type', 'hysteria');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_down_mbps', _('Max download speed'),
			_('Max download speed in Mbps.'));
		o.datatype = 'uinteger';
		o.depends('type', 'hysteria');
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_up_mbps', _('Max upload speed'),
			_('Max upload speed in Mbps.'));
		o.datatype = 'uinteger';
		o.depends('type', 'hysteria');
		o.modalonly = true;

		o = s.option(form.ListValue, 'hysteria_auth_type', _('Authentication type'));
		o.value('disabled', _('Disable'));
		o.value('base64', _('Base64'));
		o.value('string', _('String'));
		o.default = 'disabled';
		o.depends('type', 'hysteria');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_auth_payload', _('Authentication payload'));
		o.depends({'type': 'hysteria', 'hysteria_auth_type': 'base64'});
		o.depends({'type': 'hysteria', 'hysteria_auth_type': 'string'});
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_obfs_password', _('Obfuscate password'));
		o.depends('type', 'hysteria');
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_recv_window_conn', _('QUIC stream receive window'),
			_('The QUIC stream-level flow control window for receiving data.'));
		o.datatype = 'uinteger';
		o.default = '67108864';
		o.depends('type', 'hysteria');
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_recv_window_client', _('QUIC connection receive window'),
			_('The QUIC connection-level flow control window for receiving data.'));
		o.datatype = 'uinteger';
		o.default = '15728640';
		o.depends('type', 'hysteria');
		o.modalonly = true;

		o = s.option(form.Value, 'hysteria_max_conn_client', _('QUIC maximum concurrent bidirectional streams'),
			_('The maximum number of QUIC concurrent bidirectional streams that a peer is allowed to open.'));
		o.datatype = 'uinteger';
		o.default = '1024';
		o.depends('type', 'hysteria');
		o.modalonly = true;

		o = s.option(form.Flag, 'hysteria_disable_mtu_discovery', _('Disable Path MTU discovery'),
			_('Disables Path MTU Discovery (RFC 8899). Packets will then be at most 1252 (IPv4) / 1232 (IPv6) bytes in size.'));
		o.default = o.disabled;
		o.depends('type', 'hysteria');
		o.modalonly = true;
		/* Hysteria config end */

		/* Shadowsocks config */
		o = s.option(form.ListValue, 'shadowsocks_encrypt_method', _('Encrypt method'));
		for (var i of hp.shadowsocks_encrypt_methods)
			o.value(i);
		o.default = 'aes-128-gcm';
		o.depends('type', 'shadowsocks');
		o.modalonly = true;

		/* VLESS / VMess config start */
		o = s.option(form.Value, 'uuid', _('UUID'));
		o.depends('type', 'vless');
		o.depends('type', 'vmess');
		o.validate = hp.validateUUID;
		o.modalonly = true;

		o = s.option(form.ListValue, 'vless_flow', _('Flow'));
		o.value('', _('None'));
		o.value('xtls-rprx-vision');
		o.depends('type', 'vless');
		o.modalonly = true;

		o = s.option(form.Value, 'vmess_alterid', _('Alter ID'),
			_('Legacy protocol support (VMess MD5 Authentication) is provided for compatibility purposes only, use of alterId > 1 is not recommended.'));
		o.datatype = 'uinteger';
		o.depends('type', 'vmess');
		o.modalonly = true;
		/* VMess config end */

		/* Transport config start */
		o = s.option(form.ListValue, 'transport', _('Transport'),
			_('No TCP transport, plain HTTP is merged into the HTTP transport.'));
		o.value('', _('None'));
		o.value('grpc', _('gRPC'));
		o.value('http', _('HTTP'));
		o.value('quic', _('QUIC'));
		o.value('ws', _('WebSocket'));
		o.onchange = function(ev, section_id, value) {
			var desc = this.map.findElement('id', 'cbid.homeproxy.%s.transport'.format(section_id)).nextElementSibling;
			if (value === 'http')
				desc.innerHTML = _('TLS is not enforced. If TLS is not configured, plain HTTP 1.1 is used.');
			else if (value === 'quic')
				desc.innerHTML = _('No additional encryption support: It\'s basically duplicate encryption.');
			else
				desc.innerHTML = _('No TCP transport, plain HTTP is merged into the HTTP transport.');
		}
		o.depends('type', 'trojan');
		o.depends('type', 'vless');
		o.depends('type', 'vmess');
		o.modalonly = true;

		/* gRPC config */
		o = s.option(form.Value, 'grpc_servicename', _('gRPC service name'));
		o.depends('transport', 'grpc');
		o.modalonly = true;

		/* HTTP config start */
		o = s.option(form.DynamicList, 'http_host', _('Host'));
		o.datatype = 'hostname';
		o.depends('transport', 'http');
		o.modalonly = true;

		o = s.option(form.Value, 'http_path', _('Path'));
		o.depends('transport', 'http');
		o.modalonly = true;

		o = s.option(form.Value, 'http_method', _('Method'));
		o.depends('transport', 'http');
		o.modalonly = true;
		/* HTTP config end */

		/* WebSocket config start */
		o = s.option(form.Value, 'ws_host', _('Host'));
		o.depends('transport', 'ws');
		o.modalonly = true;

		o = s.option(form.Value, 'ws_path', _('Path'));
		o.depends('transport', 'ws');
		o.modalonly = true;

		o = s.option(form.Value, 'websocket_early_data', _('Early data'),
			_('Allowed payload size is in the request.'));
		o.datatype = 'uinteger';
		o.value('2048');
		o.depends('transport', 'ws');
		o.modalonly = true;

		o = s.option(form.Value, 'websocket_early_data_header', _('Early data header name'),
			_('Early data is sent in path instead of header by default.') +
			'<br/>' +
			_('To be compatible with Xray-core, set this to <code>Sec-WebSocket-Protocol</code>.'));
		o.value('Sec-WebSocket-Protocol');
		o.depends('transport', 'ws');
		o.modalonly = true;
		/* WebSocket config end */

		/* Transport config end */

		/* TLS config start */
		o = s.option(form.Flag, 'tls', _('TLS'));
		o.default = o.disabled;
		o.depends('type', 'http');
		o.depends('type', 'hysteria');
		o.depends('type', 'naive');
		o.depends('type', 'trojan');
		o.depends('type', 'vless');
		o.depends('type', 'vmess');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'tls_sni', _('TLS SNI'),
			_('Used to verify the hostname on the returned certificates unless insecure is given.'));
		o.depends('tls', '1');
		o.modalonly = true;

		o = s.option(form.DynamicList, 'tls_alpn', _('TLS ALPN'),
			_('List of supported application level protocols, in order of preference.'));
		o.depends('tls', '1');
		o.modalonly = true;

		o = s.option(form.ListValue, 'tls_min_version', _('Minimum TLS version'),
			_('The minimum TLS version that is acceptable.'));
		o.value('', _('default'));
		for (var i of hp.tls_versions)
			o.value(i);
		o.depends('tls', '1');
		o.modalonly = true;

		o = s.option(form.ListValue, 'tls_max_version', _('Maximum TLS version'),
			_('The maximum TLS version that is acceptable.'));
		o.value('', _('default'));
		for (var i of hp.tls_versions)
			o.value(i);
		o.depends('tls', '1');
		o.modalonly = true;

		o = s.option(form.MultiValue, 'tls_cipher_suites', _('Cipher suites'),
			_('The elliptic curves that will be used in an ECDHE handshake, in preference order. If empty, the default will be used.'));
		for (var i of hp.tls_cipher_suites)
			o.value(i);
		o.depends('tls', '1');
		o.optional = true;
		o.modalonly = true;

		if (data[1].with_acme) {
			o = s.option(form.Flag, 'tls_acme', _('Enable ACME'),
				_('Use ACME TLS certificate issuer.'));
			o.default = o.disabled;
			o.depends('tls', '1');
			o.modalonly = true;

			o = s.option(form.DynamicList, 'tls_acme_domain', _('Domains'));
			o.datatype = 'hostname';
			o.depends('tls_acme', '1');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_dsn', _('Default server name'),
				_('Server name to use when choosing a certificate if the ClientHello\'s ServerName field is empty.'));
			o.depends('tls_acme', '1');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_email', _('Email'),
				_('The email address to use when creating or selecting an existing ACME server account.'));
			o.depends('tls_acme', '1');
			o.validate = function(section_id, value) {
				if (section_id) {
					if (!value)
						return _('Expecting: %s').format('non-empty value');
					else if (!value.match(/^[^\s@]+@[^\s@]+\.[^\s@]+$/))
						return _('Expecting: %s').format('valid email address');
				}

				return true;
			}
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_provider', _('CA provider'),
				_('The ACME CA provider to use.'));
			o.value('letsencrypt', _('Let\'s Encrypt'));
			o.value('zerossl', _('ZeroSSL'));
			o.depends('tls_acme', '1');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Flag, 'tls_acme_dhc', _('Disable HTTP challenge'));
			o.default = o.disabled;
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.Flag, 'tls_acme_dtac', _('Disable TLS ALPN challenge'));
			o.default = o.disabled;
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_ahp', _('Alternative HTTP port'),
				_('The alternate port to use for the ACME HTTP challenge; if non-empty, this port will be used instead of 80 to spin up a listener for the HTTP challenge.'));
			o.datatype = 'port';
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_atp', _('Alternative TLS port'),
				_('The alternate port to use for the ACME TLS-ALPN challenge; the system must forward 443 to this port for challenge to succeed.'));
			o.datatype = 'port';
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.Flag, 'tls_acme_external_account', _('External Account Binding'),
				_('EAB (External Account Binding) contains information necessary to bind or map an ACME account to some other account known by the CA.' +
				'<br/>External account bindings are "used to associate an ACME account with an existing account in a non-ACME system, such as a CA customer database.'));
			o.default = o.disabled;
			o.depends('tls_acme', '1');
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_ea_keyid', _('External account key ID'));
			o.depends('tls_acme_external_account', '1');
			o.rmempty = false;
			o.modalonly = true;

			o = s.option(form.Value, 'tls_acme_ea_mackey', _('External account MAC key'));
			o.depends('tls_acme_external_account', '1');
			o.rmempty = false;
			o.modalonly = true;
		}

		o = s.option(form.Value, 'tls_cert_path', _('Certificate path'),
			_('The server public key, in PEM format.'));
		o.value('/etc/homeproxy/certs/server_publickey.pem');
		o.depends({'tls': '1', 'tls_acme': null});
		o.depends({'tls': '1', 'tls_acme': '0'});
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Button, '_upload_cert', _('Upload certificate'),
			_('<strong>Save your configuration before uploading files!</strong>'));
		o.inputstyle = 'action';
		o.inputtitle = _('Upload...');
		o.depends({'tls': '1', 'tls_cert_path': '/etc/homeproxy/certs/server_publickey.pem'});
		o.onclick = L.bind(hp.uploadCertificate, this, _('certificate'), 'server_publickey');
		o.modalonly = true;

		o = s.option(form.Value, 'tls_key_path', _('Key path'),
			_('The server private key, in PEM format.'));
		o.value('/etc/homeproxy/certs/server_privatekey.pem');
		o.depends({'tls': '1', 'tls_acme': null});
		o.depends({'tls': '1', 'tls_acme': '0'});
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Button, '_upload_key', _('Upload key'),
			_('<strong>Save your configuration before uploading files!</strong>'));
		o.inputstyle = 'action';
		o.inputtitle = _('Upload...');
		o.depends({'tls': '1', 'tls_key_path': '/etc/homeproxy/certs/server_privatekey.pem'});
		o.onclick = L.bind(hp.uploadCertificate, this, _('private key'), 'server_privatekey');
		o.modalonly = true;
		/* TLS config end */

		/* Extra settings start */
		o = s.option(form.Flag, 'tcp_fast_open', _('TCP fast open'),
			_('Enable tcp fast open for listener.'));
		o.default = o.disabled;
		o.depends({'network': 'udp', '!reverse': true});
		o.modalonly = true;

		o = s.option(form.Flag, 'udp_fragment', _('UDP Fragment'),
			_('Enable UDP fragmentation.'));
		o.default = o.disabled;
		o.depends({'network': 'tcp', '!reverse': true});
		o.modalonly = true;

		o = s.option(form.Flag, 'sniff_override', _('Override destination'),
			_('Override the connection destination address with the sniffed domain.'));
		o.rmempty = false;

		o = s.option(form.ListValue, 'domain_strategy', _('Domain strategy'),
			_('If set, the requested domain name will be resolved to IP before routing.'));
		for (var i in hp.dns_strategy)
			o.value(i, hp.dns_strategy[i])
		o.modalonly = true;

		o = s.option(form.Flag, 'proxy_protocol', _('Proxy protocol'),
			_('Parse Proxy Protocol in the connection header.'));
		o.default = o.disabled;
		o.depends({'network': 'udp', '!reverse': true});
		o.modalonly = true;

		o = s.option(form.Flag, 'proxy_protocol_accept_no_header', _('Accept no header'),
			_('Accept connections without Proxy Protocol header.'));
		o.default = o.disabled;
		o.depends('proxy_protocol', '1');
		o.modalonly = true;

		o = s.option(form.ListValue, 'network', _('Network'));
		o.value('tcp', _('TCP'));
		o.value('udp', _('UDP'));
		o.value('', _('Both'));
		o.depends('type', 'naive');
		o.depends('type', 'shadowsocks');
		o.modalonly = true;
		/* Extra settings end */

		return m.render();
	}
});
