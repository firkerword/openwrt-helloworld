local m, s = ...

local api = require "luci.passwall.api"

if not api.is_finded("sslocal") then
	return
end

local type_name = "SS-Rust"

local option_prefix = "ssrust_"

local function option_name(name)
	return option_prefix .. name
end

local function rm_prefix_cfgvalue(self, section)
	if self.option:find(option_prefix) == 1 then
		return m:get(section, self.option:sub(1 + #option_prefix))
	end
end
local function rm_prefix_write(self, section, value)
	if s.fields["type"]:formvalue(arg[1]) == type_name then
		if self.option:find(option_prefix) == 1 then
			m:set(section, self.option:sub(1 + #option_prefix), value)
		end
	end
end
local function rm_prefix_remove(self, section, value)
	if s.fields["type"]:formvalue(arg[1]) == type_name then
		if self.option:find(option_prefix) == 1 then
			m:del(section, self.option:sub(1 + #option_prefix))
		end
	end
end

local ssrust_encrypt_method_list = {
	"plain", "none",
	"aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305",
	"2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305"
}

-- [[ Shadowsocks Rust ]]

s.fields["type"]:value(type_name, translate("Shadowsocks Rust"))

o = s:option(Value, option_name("address"), translate("Address (Support Domain Name)"))

o = s:option(Value, option_name("port"), translate("Port"))
o.datatype = "port"

o = s:option(Value, option_name("password"), translate("Password"))
o.password = true

o = s:option(Value, option_name("method"), translate("Encrypt Method"))
for a, t in ipairs(ssrust_encrypt_method_list) do o:value(t) end

o = s:option(Value, option_name("timeout"), translate("Connection Timeout"))
o.datatype = "uinteger"
o.default = 300

o = s:option(ListValue, option_name("tcp_fast_open"), "TCP " .. translate("Fast Open"), translate("Need node support required"))
o:value("false")
o:value("true")

o = s:option(ListValue, option_name("plugin"), translate("plugin"))
o:value("none", translate("none"))
if api.is_finded("xray-plugin") then o:value("xray-plugin") end
if api.is_finded("v2ray-plugin") then o:value("v2ray-plugin") end
if api.is_finded("obfs-local") then o:value("obfs-local") end

o = s:option(Value, option_name("plugin_opts"), translate("opts"))
o:depends({ [option_name("plugin")] = "xray-plugin"})
o:depends({ [option_name("plugin")] = "v2ray-plugin"})
o:depends({ [option_name("plugin")] = "obfs-local"})

for key, value in pairs(s.fields) do
	if key:find(option_prefix) == 1 then
		if not s.fields[key].not_rewrite then
			s.fields[key].cfgvalue = rm_prefix_cfgvalue
			s.fields[key].write = rm_prefix_write
			s.fields[key].remove = rm_prefix_remove
		end

		local deps = s.fields[key].deps
		if #deps > 0 then
			for index, value in ipairs(deps) do
				deps[index]["type"] = type_name
			end
		else
			s.fields[key]:depends({ type = type_name })
		end
	end
end
