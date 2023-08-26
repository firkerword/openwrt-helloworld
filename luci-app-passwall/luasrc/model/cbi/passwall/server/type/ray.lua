local m, s = ...

local api = require "luci.passwall.api"

if not api.is_finded("xray") and not api.is_finded("v2ray")then
	return
end

local option_prefix = "xray_"

local function option_name(name)
	return option_prefix .. name
end

local function rm_prefix_cfgvalue(self, section)
	if self.option:find(option_prefix) == 1 then
		return m:get(section, self.option:sub(1 + #option_prefix))
	end
end
local function rm_prefix_write(self, section, value)
	if self.option:find(option_prefix) == 1 then
		m:set(section, self.option:sub(1 + #option_prefix), value)
	end
end

local function add_xray_depends(o, field, value)
	local deps = { type = "Xray" }
	if field then
		if type(field) == "string" then
			deps[field] = value
		else
			for key, value in pairs(field) do
				deps[key] = value
			end
		end
	end
	o:depends(deps)
end

local function add_v2ray_depends(o, field, value)
	local deps = { type = "V2ray" }
	if field then
		if type(field) == "string" then
			deps[field] = value
		else
			for key, value in pairs(field) do
				deps[key] = value
			end
		end
	end
	o:depends(deps)
end

local v_ss_encrypt_method_list = {
	"aes-128-gcm", "aes-256-gcm", "chacha20-poly1305"
}

local x_ss_encrypt_method_list = {
	"aes-128-gcm", "aes-256-gcm", "chacha20-poly1305", "xchacha20-poly1305", "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305"
}

local header_type_list = {
	"none", "srtp", "utp", "wechat-video", "dtls", "wireguard"
}

-- [[ Xray ]]

if api.is_finded("v2ray") then
	s.fields["type"]:value("V2ray", translate("V2ray"))
end
if api.is_finded("xray") then
	s.fields["type"]:value("Xray", translate("Xray"))
end

o = s:option(ListValue, "xray_protocol", translate("Protocol"))
o:value("vmess", "Vmess")
o:value("vless", "VLESS")
o:value("http", "HTTP")
o:value("socks", "Socks")
o:value("shadowsocks", "Shadowsocks")
o:value("trojan", "Trojan")
o:value("dokodemo-door", "dokodemo-door")
add_xray_depends(o)
add_v2ray_depends(o)
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(Value, "xray_port", translate("Listen Port"))
o.datatype = "port"
add_xray_depends(o)
add_v2ray_depends(o)
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(Flag, "xray_auth", translate("Auth"))
o.validate = function(self, value, t)
	if value and value == "1" then
		local user_v = s.fields["xray_username"]:formvalue(t) or ""
		local pass_v = s.fields["xray_password"]:formvalue(t) or ""
		if user_v == "" or pass_v == "" then
			return nil, translate("Username and Password must be used together!")
		end
	end
	return value
end
add_xray_depends(o, { xray_protocol = "socks" })
add_xray_depends(o, { xray_protocol = "http" })
add_v2ray_depends(o, { xray_protocol = "socks" })
add_v2ray_depends(o, { xray_protocol = "http" })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(Value, "xray_username", translate("Username"))
add_xray_depends(o, { xray_auth = true })
add_v2ray_depends(o, { xray_auth = true })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(Value, "xray_password", translate("Password"))
o.password = true
add_xray_depends(o, { xray_auth = true })
add_v2ray_depends(o, { xray_auth = true })
add_xray_depends(o, { xray_protocol = "shadowsocks" })
add_v2ray_depends(o, { xray_protocol = "shadowsocks" })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(ListValue, "d_protocol", translate("Destination protocol"))
o:value("tcp", "TCP")
o:value("udp", "UDP")
o:value("tcp,udp", "TCP,UDP")
add_v2ray_depends(o, { xray_protocol = "dokodemo-door" })
add_xray_depends(o, { xray_protocol = "dokodemo-door" })

o = s:option(Value, "d_address", translate("Destination address"))
add_v2ray_depends(o, { xray_protocol = "dokodemo-door" })
add_xray_depends(o, { xray_protocol = "dokodemo-door" })

o = s:option(Value, "d_port", translate("Destination port"))
o.datatype = "port"
add_v2ray_depends(o, { xray_protocol = "dokodemo-door" })
add_xray_depends(o, { xray_protocol = "dokodemo-door" })

o = s:option(Value, "decryption", translate("Encrypt Method"))
o.default = "none"
add_v2ray_depends(o, { xray_protocol = "vless" })
add_xray_depends(o, { xray_protocol = "vless" })

o = s:option(ListValue, "v_ss_encrypt_method", translate("Encrypt Method"))
for a, t in ipairs(v_ss_encrypt_method_list) do o:value(t) end
add_v2ray_depends(o, { xray_protocol = "shadowsocks" })
function o.cfgvalue(self, section)
	return m:get(section, "method")
end
function o.write(self, section, value)
	m:set(section, "method", value)
end

o = s:option(ListValue, "x_ss_encrypt_method", translate("Encrypt Method"))
for a, t in ipairs(x_ss_encrypt_method_list) do o:value(t) end
add_xray_depends(o, { xray_protocol = "shadowsocks" })
function o.cfgvalue(self, section)
	return m:get(section, "method")
end
function o.write(self, section, value)
	m:set(section, "method", value)
end

o = s:option(Flag, "iv_check", translate("IV Check"))
add_v2ray_depends(o, { xray_protocol = "shadowsocks" })
add_xray_depends(o, { xray_protocol = "shadowsocks" })

o = s:option(ListValue, "ss_network", translate("Transport"))
o.default = "tcp,udp"
o:value("tcp", "TCP")
o:value("udp", "UDP")
o:value("tcp,udp", "TCP,UDP")
add_v2ray_depends(o, { xray_protocol = "shadowsocks" })
add_xray_depends(o, { xray_protocol = "shadowsocks" })

o = s:option(Flag, "udp_forward", translate("UDP Forward"))
o.default = "1"
o.rmempty = false
add_v2ray_depends(o, { xray_protocol = "socks" })
add_xray_depends(o, { xray_protocol = "socks" })

o = s:option(DynamicList, "xray_uuid", translate("ID") .. "/" .. translate("Password"))
for i = 1, 3 do
	o:value(api.gen_uuid(1))
end
add_v2ray_depends(o, { xray_protocol = "vmess" })
add_v2ray_depends(o, { xray_protocol = "vless" })
add_v2ray_depends(o, { xray_protocol = "trojan" })
add_xray_depends(o, { xray_protocol = "vmess" })
add_xray_depends(o, { xray_protocol = "vless" })
add_xray_depends(o, { xray_protocol = "trojan" })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(Flag, "xray_tls", translate("TLS"))
o.default = 0
o.validate = function(self, value, t)
	if value then
		if value == "1" then
			local ca = s.fields["xray_tls_certificateFile"]:formvalue(t) or ""
			local key = s.fields["xray_tls_keyFile"]:formvalue(t) or ""
			if ca == "" or key == "" then
				return nil, translate("Public key and Private key path can not be empty!")
			end
		end
		return value
	end
end
add_v2ray_depends(o, { xray_protocol = "vmess" })
add_v2ray_depends(o, { xray_protocol = "vless" })
add_v2ray_depends(o, { xray_protocol = "socks" })
add_v2ray_depends(o, { xray_protocol = "shadowsocks" })
add_v2ray_depends(o, { xray_protocol = "trojan" })
add_xray_depends(o, { xray_protocol = "vmess" })
add_xray_depends(o, { xray_protocol = "vless" })
add_xray_depends(o, { xray_protocol = "socks" })
add_xray_depends(o, { xray_protocol = "shadowsocks" })
add_xray_depends(o, { xray_protocol = "trojan" })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(Value, "tlsflow", translate("flow"))
o.default = ""
o:value("", translate("Disable"))
o:value("xtls-rprx-vision")
o:value("xtls-rprx-vision-udp443")
add_xray_depends(o, { xray_protocol = "vless", xray_tls = true })

o = s:option(ListValue, "alpn", translate("alpn"))
o.default = "h2,http/1.1"
o:value("h2,http/1.1")
o:value("h2")
o:value("http/1.1")
add_v2ray_depends(o, { xray_tls = true })
add_xray_depends(o, { xray_tls = true })

-- o = s:option(Value, "minversion", translate("minversion"))
-- o.default = "1.3"
-- o:value("1.3")
--add_v2ray_depends(o, { xray_tls = true })
--add_xray_depends(o, { xray_tls = true })

-- [[ TLS部分 ]] --

o = s:option(FileUpload, "xray_tls_certificateFile", translate("Public key absolute path"), translate("as:") .. "/etc/ssl/fullchain.pem")
o.default = m:get(s.section, "tls_certificateFile") or "/etc/config/ssl/" .. arg[1] .. ".pem"
add_v2ray_depends(o, { xray_tls = true })
add_xray_depends(o, { xray_tls = true })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write
o.validate = function(self, value, t)
	if value and value ~= "" then
		if not nixio.fs.access(value) then
			return nil, translate("Can't find this file!")
		else
			return value
		end
	end
	return nil
end

o = s:option(FileUpload, "xray_tls_keyFile", translate("Private key absolute path"), translate("as:") .. "/etc/ssl/private.key")
o.default = m:get(s.section, "tls_keyFile") or "/etc/config/ssl/" .. arg[1] .. ".key"
add_v2ray_depends(o, { xray_tls = true })
add_xray_depends(o, { xray_tls = true })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write
o.validate = function(self, value, t)
	if value and value ~= "" then
		if not nixio.fs.access(value) then
			return nil, translate("Can't find this file!")
		else
			return value
		end
	end
	return nil
end

o = s:option(ListValue, "transport", translate("Transport"))
o:value("tcp", "TCP")
o:value("mkcp", "mKCP")
o:value("ws", "WebSocket")
o:value("h2", "HTTP/2")
o:value("ds", "DomainSocket")
o:value("quic", "QUIC")
o:value("grpc", "gRPC")
add_v2ray_depends(o, { xray_protocol = "vmess" })
add_v2ray_depends(o, { xray_protocol = "vless" })
add_v2ray_depends(o, { xray_protocol = "socks" })
add_v2ray_depends(o, { xray_protocol = "shadowsocks" })
add_v2ray_depends(o, { xray_protocol = "trojan" })
add_xray_depends(o, { xray_protocol = "vmess" })
add_xray_depends(o, { xray_protocol = "vless" })
add_xray_depends(o, { xray_protocol = "socks" })
add_xray_depends(o, { xray_protocol = "shadowsocks" })
add_xray_depends(o, { xray_protocol = "trojan" })

-- [[ WebSocket部分 ]]--

o = s:option(Value, "xray_ws_host", translate("WebSocket Host"))
add_v2ray_depends(o, { transport = "ws" })
add_xray_depends(o, { transport = "ws" })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(Value, "xray_ws_path", translate("WebSocket Path"))
add_v2ray_depends(o, { transport = "ws" })
add_xray_depends(o, { transport = "ws" })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

-- [[ HTTP/2部分 ]]--

o = s:option(Value, "xray_h2_host", translate("HTTP/2 Host"))
add_v2ray_depends(o, { transport = "h2" })
add_xray_depends(o, { transport = "h2" })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(Value, "xray_h2_path", translate("HTTP/2 Path"))
add_v2ray_depends(o, { transport = "h2" })
add_xray_depends(o, { transport = "h2" })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

-- [[ TCP部分 ]]--

-- TCP伪装
o = s:option(ListValue, "tcp_guise", translate("Camouflage Type"))
o:value("none", "none")
o:value("http", "http")
add_v2ray_depends(o, { transport = "tcp" })
add_xray_depends(o, { transport = "tcp" })

-- HTTP域名
o = s:option(DynamicList, "tcp_guise_http_host", translate("HTTP Host"))
add_v2ray_depends(o, { tcp_guise = "http" })
add_xray_depends(o, { tcp_guise = "http" })

-- HTTP路径
o = s:option(DynamicList, "tcp_guise_http_path", translate("HTTP Path"))
add_v2ray_depends(o, { tcp_guise = "http" })
add_xray_depends(o, { tcp_guise = "http" })

-- [[ mKCP部分 ]]--

o = s:option(ListValue, "mkcp_guise", translate("Camouflage Type"), translate('<br />none: default, no masquerade, data sent is packets with no characteristics.<br />srtp: disguised as an SRTP packet, it will be recognized as video call data (such as FaceTime).<br />utp: packets disguised as uTP will be recognized as bittorrent downloaded data.<br />wechat-video: packets disguised as WeChat video calls.<br />dtls: disguised as DTLS 1.2 packet.<br />wireguard: disguised as a WireGuard packet. (not really WireGuard protocol)'))
for a, t in ipairs(header_type_list) do o:value(t) end
add_v2ray_depends(o, { transport = "mkcp" })
add_xray_depends(o, { transport = "mkcp" })

o = s:option(Value, "mkcp_mtu", translate("KCP MTU"))
o.default = "1350"
add_v2ray_depends(o, { transport = "mkcp" })
add_xray_depends(o, { transport = "mkcp" })

o = s:option(Value, "mkcp_tti", translate("KCP TTI"))
o.default = "20"
add_v2ray_depends(o, { transport = "mkcp" })
add_xray_depends(o, { transport = "mkcp" })

o = s:option(Value, "mkcp_uplinkCapacity", translate("KCP uplinkCapacity"))
o.default = "5"
add_v2ray_depends(o, { transport = "mkcp" })
add_xray_depends(o, { transport = "mkcp" })

o = s:option(Value, "mkcp_downlinkCapacity", translate("KCP downlinkCapacity"))
o.default = "20"
add_v2ray_depends(o, { transport = "mkcp" })
add_xray_depends(o, { transport = "mkcp" })

o = s:option(Flag, "mkcp_congestion", translate("KCP Congestion"))
add_v2ray_depends(o, { transport = "mkcp" })
add_xray_depends(o, { transport = "mkcp" })

o = s:option(Value, "mkcp_readBufferSize", translate("KCP readBufferSize"))
o.default = "1"
add_v2ray_depends(o, { transport = "mkcp" })
add_xray_depends(o, { transport = "mkcp" })

o = s:option(Value, "mkcp_writeBufferSize", translate("KCP writeBufferSize"))
o.default = "1"
add_v2ray_depends(o, { transport = "mkcp" })
add_xray_depends(o, { transport = "mkcp" })

o = s:option(Value, "mkcp_seed", translate("KCP Seed"))
add_v2ray_depends(o, { transport = "mkcp" })
add_xray_depends(o, { transport = "mkcp" })

-- [[ DomainSocket部分 ]]--

o = s:option(Value, "ds_path", "Path", translate("A legal file path. This file must not exist before running."))
add_v2ray_depends(o, { transport = "ds" })
add_xray_depends(o, { transport = "ds" })

-- [[ QUIC部分 ]]--
o = s:option(ListValue, "quic_security", translate("Encrypt Method"))
o:value("none")
o:value("aes-128-gcm")
o:value("chacha20-poly1305")
add_v2ray_depends(o, { transport = "quic" })
add_xray_depends(o, { transport = "quic" })

o = s:option(Value, "quic_key", translate("Encrypt Method") .. translate("Key"))
add_v2ray_depends(o, { transport = "quic" })
add_xray_depends(o, { transport = "quic" })

o = s:option(ListValue, "quic_guise", translate("Camouflage Type"))
for a, t in ipairs(header_type_list) do o:value(t) end
add_v2ray_depends(o, { transport = "quic" })
add_xray_depends(o, { transport = "quic" })

-- [[ gRPC部分 ]]--
o = s:option(Value, "grpc_serviceName", "ServiceName")
add_v2ray_depends(o, { transport = "grpc" })
add_xray_depends(o, { transport = "grpc" })

o = s:option(Flag, "acceptProxyProtocol", translate("acceptProxyProtocol"), translate("Whether to receive PROXY protocol, when this node want to be fallback or forwarded by proxy, it must be enable, otherwise it cannot be used."))
add_v2ray_depends(o, { transport = "tcp" })
add_v2ray_depends(o, { transport = "ws" })
add_xray_depends(o, { transport = "tcp" })
add_xray_depends(o, { transport = "ws" })

-- [[ Fallback部分 ]]--
o = s:option(Flag, "fallback", translate("Fallback"))
add_v2ray_depends(o, { xray_protocol = "vless", transport = "tcp" })
add_v2ray_depends(o, { xray_protocol = "trojan", transport = "tcp" })
add_xray_depends(o, { xray_protocol = "vless", transport = "tcp" })
add_xray_depends(o, { xray_protocol = "trojan", transport = "tcp" })

--[[
o = s:option(Value, "fallback_alpn", "Fallback alpn")
add_v2ray_depends(o, { fallback = true })
add_xray_depends(o, { fallback = true })

o = s:option(Value, "fallback_path", "Fallback path")
add_v2ray_depends(o, { fallback = true })
add_xray_depends(o, { fallback = true })

o = s:option(Value, "fallback_dest", "Fallback dest")
add_v2ray_depends(o, { fallback = true })
add_xray_depends(o, { fallback = true })

o = s:option(Value, "fallback_xver", "Fallback xver")
o.default = 0
add_v2ray_depends(o, { fallback = true })
add_xray_depends(o, { fallback = true })
]]--

o = s:option(DynamicList, "fallback_list", "Fallback", translate("dest,path"))
add_v2ray_depends(o, { fallback = true })
add_xray_depends(o, { fallback = true })

o = s:option(Flag, "bind_local", translate("Bind Local"), translate("When selected, it can only be accessed locally, It is recommended to turn on when using reverse proxies or be fallback."))
o.default = "0"
add_v2ray_depends(o)
add_xray_depends(o)

o = s:option(Flag, "accept_lan", translate("Accept LAN Access"), translate("When selected, it can accessed lan , this will not be safe!"))
o.default = "0"
add_v2ray_depends(o)
add_xray_depends(o)

local nodes_table = {}
for k, e in ipairs(api.get_valid_nodes()) do
	if e.node_type == "normal" and (e.type == "V2ray" or e.type == "Xray") then
		nodes_table[#nodes_table + 1] = {
			id = e[".name"],
			remarks = e["remark"]
		}
	end
end

o = s:option(ListValue, "outbound_node", translate("outbound node"))
o:value("nil", translate("Close"))
o:value("_socks", translate("Custom Socks"))
o:value("_http", translate("Custom HTTP"))
o:value("_iface", translate("Custom Interface") .. " (Only Support Xray)")
for k, v in pairs(nodes_table) do o:value(v.id, v.remarks) end
o.default = "nil"
add_v2ray_depends(o)
add_xray_depends(o)

o = s:option(Value, "outbound_node_address", translate("Address (Support Domain Name)"))
add_v2ray_depends(o, { outbound_node = "_socks"})
add_v2ray_depends(o, { outbound_node = "_http"})
add_xray_depends(o, { outbound_node = "_socks"})
add_xray_depends(o, { outbound_node = "_http"})

o = s:option(Value, "outbound_node_port", translate("Port"))
o.datatype = "port"
add_v2ray_depends(o, { outbound_node = "_socks"})
add_v2ray_depends(o, { outbound_node = "_http"})
add_xray_depends(o, { outbound_node = "_socks"})
add_xray_depends(o, { outbound_node = "_http"})

o = s:option(Value, "outbound_node_username", translate("Username"))
add_v2ray_depends(o, { outbound_node = "_socks"})
add_v2ray_depends(o, { outbound_node = "_http"})
add_xray_depends(o, { outbound_node = "_socks"})
add_xray_depends(o, { outbound_node = "_http"})

o = s:option(Value, "outbound_node_password", translate("Password"))
o.password = true
add_v2ray_depends(o, { outbound_node = "_socks"})
add_v2ray_depends(o, { outbound_node = "_http"})
add_xray_depends(o, { outbound_node = "_socks"})
add_xray_depends(o, { outbound_node = "_http"})

o = s:option(Value, "outbound_node_iface", translate("Interface"))
o.default = "eth1"
add_v2ray_depends(o, { outbound_node = "_iface"})
add_xray_depends(o, { outbound_node = "_iface"})

o = s:option(Flag, "xray_log", translate("Log"))
o.default = "1"
add_v2ray_depends(o)
add_xray_depends(o)
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write

o = s:option(ListValue, "xray_loglevel", translate("Log Level"))
o.default = "warning"
o:value("debug")
o:value("info")
o:value("warning")
o:value("error")
add_v2ray_depends(o, { xray_log = true })
add_xray_depends(o, { xray_log = true })
o.cfgvalue = rm_prefix_cfgvalue
o.write = rm_prefix_write
