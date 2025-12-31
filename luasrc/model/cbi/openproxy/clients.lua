
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

return m
