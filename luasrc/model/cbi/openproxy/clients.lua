
m = Map("openproxy", translate("Client Proxy Control"), translate("Manage devices to have their own proxy groups in the dashboard."))

s = m:section(TypedSection, "client", translate("Clients"))
s.template = "cbi/tblsection"
s.anonymous = true
s.addremove = true
s.sortable  = true

o = s:option(Flag, "enable", translate("Enable"))
o.rmempty = false
o.default = "1"

o = s:option(Value, "name", translate("Name"))
o.rmempty = false
o.description = translate("Name of the device (will be the Proxy Group name)")

o = s:option(Value, "ip_addr", translate("IP Address"))
o.datatype = "ipaddr"
o.rmempty = false
o.description = translate("Static IP address of the device")

-- Simple parsing to get available proxy groups from current config
local config_file = uci:get("openproxy", "config", "config_path")
local fs = require "nixio.fs"

o = s:option(MultiValue, "proxies", translate("Proxy Groups"))
o.description = translate("Select which proxy groups/providers should be available for this device.")
o.optional = false
o.rmempty = false
o:value("DIRECT")
o:value("REJECT")
o:value("⭐Default Node Group⭐") -- Default fallback

if config_file and fs.access(config_file) then
    local file = io.open(config_file, "r")
    if file then
        local in_groups = false
        for line in file:lines() do
            -- Very basic state machine to find proxy-groups section
            if line:match("^proxy%-groups:") then
                in_groups = true
            elseif line:match("^%S") and not line:match("^%s*#") then
                -- Exit if we hit another top-level section (no indentation)
                in_groups = false
            end

            if in_groups then
                local name = line:match("^%s*-%s*name:%s*(.+)")
                if name then
                    -- Trim whitespace/quotes
                    name = name:gsub("^%s*(.-)%s*$", "%1")
                    name = name:gsub("^['\"](.-)['\"]$", "%1")
                    o:value(name)
                end
            end
        end
        file:close()
    end
end
o.default = "⭐Default Node Group⭐ DIRECT"

return m
