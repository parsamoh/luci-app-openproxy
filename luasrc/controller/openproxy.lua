module("luci.controller.openproxy", package.seeall)

local uci = require("luci.model.uci").cursor()
local http = require "luci.http"
local fs = require "nixio.fs"
local sys = require "luci.sys"

local config_link = "/etc/openproxy/config.yaml"
local core_link = "/etc/openproxy/clash"
local service_name = "openproxy"
local service_log = "/tmp/openproxy.log"
local mihomo_log = "/tmp/mihomo.log"
local init_script = "/etc/init.d/openproxy"
local device_name = uci:get("system", "@system[0]", "hostname")
local device_arh = sys.exec("uname -m |tr -d '\n'")

function index()
    -- Create entry page menu
    local page_index = 1
    entry({"admin", "services", service_name}, firstchild(), _("OpenProxy"), 10).dependent = false
    entry({"admin", "services", service_name, "main"}, template("openproxy/main"), _("Main"), page_index)
    page_index = page_index + 1
    entry({"admin", "services", service_name, "editor"}, template("openproxy/editor"), _("Edit"), page_index)
    page_index = page_index + 1
    entry({"admin", "services", service_name, "options"}, cbi("openproxy/options"), _("Options"), page_index)
    page_index = page_index + 1
    entry({"admin", "services", service_name, "help"}, template("openproxy/help"), _("Help"), page_index)
    page_index = page_index + 1
    entry({"admin", "services", service_name, "logs"}, template("openproxy/logs"), _("Logs"), page_index)

    -- API Interface: Dynamically get file content
    entry({"admin", "services", service_name, "api", "file_content"}, call("api_get_file_content")).leaf = true
    entry({"admin", "services", service_name, "api", "save_file"}, call("api_save_file_content")).leaf = true
    entry({"admin", "services", service_name, "api", "delete_file"}, call("api_delete_file")).leaf = true
    entry({"admin", "services", service_name, "api", "service_apply"}, call("api_service_apply")).leaf = true
    entry({"admin", "services", service_name, "api", "dns_apply"}, call("api_dns_apply")).leaf = true
    entry({"admin", "services", service_name, "api", "config"}, call("api_get_service_config")).leaf = true
    entry({"admin", "services", service_name, "api", "dns_config"}, call("api_get_dns_config")).leaf = true
    entry({"admin", "services", service_name, "api", "status"}, call("api_service_status")).leaf = true
    entry({"admin", "services", service_name, "api", "load_editor_status"}, call("api_load_editor_status")).leaf = true
    entry({"admin", "services", service_name, "api", "update_value"}, call("api_update_value")).leaf = true
    entry({"admin", "services", service_name, "api", "backup"}, call("api_backup_config")).leaf = true
    entry({"admin", "services", service_name, "api", "get_logs"}, call("api_get_logs")).leaf = true
    entry({"admin", "services", service_name, "api", "clear_logs"}, call("api_clear_logs")).leaf = true
end

----------------------------------------------------------------------------------

function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end
function split_key(str, sep)
    local t = {}
    for str in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end
function set_uci_value(key, value)
    local keys = split_key(key, ".")
    local section = keys[1]
    local option = keys[2]
    uci:set(service_name, section, option, value)
    uci:commit(service_name)
end

--- Update configuration info
function api_update_value()
    local key = http.formvalue("key")
    local value = http.formvalue("value")
    set_uci_value(key, value)
    http.prepare_content("application/json")
    http.write_json({
        status = 1000,
        message = "Update success"
    })
end

local function get_last_log()
    local info = ""
    if fs.access(service_log) then
        info = sys.exec("tail -n1 " .. service_log .. " 2>/dev/null")
    end
    return trim(info)
end
function ltn12_popen(command)

    local fdi, fdo = nixio.pipe()
    local pid = nixio.fork()

    if pid > 0 then
        fdo:close()
        local close
        return function()
            local buffer = fdi:read(2048)
            local wpid, stat = nixio.waitpid(pid, "nohang")
            if not close and wpid and stat == "exited" then
                close = true
            end

            if buffer and #buffer > 0 then
                return buffer
            elseif close then
                fdi:close()
                return nil
            end
        end
    elseif pid == 0 then
        nixio.dup(fdo, nixio.stdout)
        fdi:close()
        fdo:close()
        nixio.exec("/bin/sh", "-c", command)
    end
end
-- Get distro info
local function get_os_release_info()
    local file = io.open("/etc/os-release", "r")
    if not file then
        return nil
    end

    local os_info = {}
    for line in file:lines() do
        local key, value = line:match("^(%S+)=(.*)$")
        if key and value then
            -- Remove quotes around the value
            value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
            os_info[key] = value
        end
    end
    file:close()
    return os_info
end

-- Check if opkg is available
local function is_opkg_available()
    local handle = io.popen("opkg --version")
    local result = handle:read("*l")
    handle:close()
    return result ~= nil
end

-- Check if apk is available
local function is_apk_available()
    local handle = io.popen("apk --version")
    local result = handle:read("*l")
    handle:close()
    return result ~= nil
end

----------------------------------------------------------------------------------
--- Function: View file content
function api_get_file_content()
    local file_path = http.formvalue("file")
    if file_path and fs.access(file_path) then
        -- JSON return http.write(fs.readfile(file_path))
        http.prepare_content("application/json")
        http.write_json({
            status = 1000,
            message = "File content",
            data = fs.readfile(file_path)
        })
        uci:set(service_name, "config", "editor_file", file_path)
        uci:commit(service_name)
    else
        http.prepare_content("application/json")
        http.write_json({
            status = 404,
            message = "File not found:".. file_path
        })
    end
end

--- Function: Save file content
function api_save_file_content()
    local file_path = http.formvalue("file")
    local content = http.formvalue("content")
    if file_path and content then
        fs.writefile(file_path, content)
        sys.call("yq e -Pi "..file_path)  -- Format yaml config file
        http.prepare_content("application/json")
        http.write_json({
            status = 1000,
            message = "File saved successfully",
            data = content
        })
    else
        http.prepare_content("application/json")
        http.write_json({
            status = 400,
            message = "Bad request"
        })
    end
end

--- Function: Delete file
function api_delete_file()
    local file_path = http.formvalue("file")
    if file_path then
        fs.unlink(file_path)-- Delete config file
        http.prepare_content("application/json")
        http.write_json({
            status = 1000,
            message = "File is deleted: ".. file_path
        })
    else
        http.prepare_content("application/json")
        http.write_json({
            status = 400,
            message = "Bad request"
        })
    end
end

--- Function: Update service config (and restart service)
function api_service_apply()
    local enable_value = http.formvalue("enable")
    local enable_ipv6 = http.formvalue("enable_ipv6")
    local enable_trans_ipv6 = http.formvalue("enable_trans_ipv6")
    local p_core = http.formvalue("core")
    local p_mode = http.formvalue("mode")
    local p_config_path = http.formvalue("config_path")
    local p_dashboard_type = http.formvalue("dashboard_type")
    if enable_value == "1" or enable_value == "true" then
        uci:set(service_name, "config", "enable", '1')
    else
        uci:set(service_name, "config", "enable", '0')
    end
    if enable_ipv6 == "1" or enable_ipv6 == "true" then
        uci:set(service_name, "config", "ipv6", '1')
    else
        uci:set(service_name, "config", "ipv6", '0')
    end
    if enable_trans_ipv6 == "1" or enable_trans_ipv6 == "true" then
        uci:set(service_name, "config", "trans_ipv6", '1')
    else
        uci:set(service_name, "config", "trans_ipv6", '0')
    end
    if p_core then
        fs.unlink(core_link) -- Delete symlink first
        fs.symlink(p_core, core_link) -- Create symlink to config file
    end
    if p_dashboard_type then
        uci:set(service_name, "config", "dashboard_type", p_dashboard_type)
    end
    uci:set(service_name, "config", "core", p_core)
    uci:set(service_name, "config", "mode", p_mode or "NAT+TPROXY")
    uci:set(service_name, "config", "config_path", p_config_path)
    uci:commit(service_name)

    sys.call(init_script.." restart >/dev/null 2>&1")
    http.prepare_content("application/json")
    http.write_json({
        status = "1000",
        message = "Parameters saved successfully"
    })
end

function api_dns_apply()
    local enable_custom_dns = http.formvalue("enable_custom_dns")
    local dns_port = http.formvalue("dns_port")
    if enable_custom_dns == "1" or enable_custom_dns == "true" then
        uci:set(service_name, "config", "enable_custom_dns", '1')
    else
        uci:set(service_name, "config", "enable_custom_dns", '0')
    end
    if #dns_port == 0 then
        dns_port = "1053"
    end
    uci:set(service_name, "config", "dns_port", dns_port)
    uci:commit(service_name)

    sys.call(init_script.." restart >/dev/null 2>&1")
    http.prepare_content("application/json")
    http.write_json({
        status = "1000",
        message = "Parameters saved successfully"
    })
end
--- Function: View service config info
function api_get_service_config()
    local status = {}

    status.enable = uci:get(service_name, "config", "enable")
    status.enable_ipv6 = uci:get(service_name, "config", "ipv6")
    status.enable_trans_ipv6 = uci:get(service_name, "config", "trans_ipv6")
    status.core = uci:get(service_name, "config", "core")
    status.mode = uci:get(service_name, "config", "mode")
    status.config_path = uci:get(service_name, "config", "config_path")
    status.dashboard_type = uci:get(service_name, "config", "dashboard_type") or "yacd"

    -- Return status info in JSON format
    http.prepare_content("application/json")
    http.write_json(status)
end

--- Function: View DNS config info
function api_get_dns_config()
    local status = {}
    status.enable_custom_dns = uci:get(service_name, "config", "enable_custom_dns")
    status.dns_port = uci:get(service_name, "config", "dns_port")
    http.prepare_content("application/json")
    http.write_json(status)
end

local os_info = get_os_release_info()

--- Function: Get compiled program architecture type
---@param arch_type string CPU architecture type
function getGoArch(arch_type)
    local arch
    if #arch_type == 0 then
        local handle = io.popen("uname -m")
        arch = handle:read("*a"):gsub("%s+", "") -- Remove extra spaces
        handle:close()
    else
        arch = arch_type
    end

    if arch == "x86_64" then
        return arch.."/amd64"
    elseif arch == "i386" or arch == "i686" then
        return arch.."/386"
    elseif arch == "armv7l" then
        return arch.."/armv7"
    elseif arch:match("^aarch64") then
        return arch.."/arm64"
    elseif arch == "ppc64le" then
        return arch.."/ppc64le"
    elseif arch == "s390x" then
        return arch.."/s390x"
    else
        return arch.."/unknown"
    end
end

--- Function: View service running status info
function api_service_status()
    local status = {}
    local process_exists = trim(sys.exec(init_script.." status"))
    if process_exists == "running" then
        status.running = true
        status.message = "openproxy is running"
    else
        status.running = false
        status.message = "openproxy stoped, reason:"..process_exists
    end
    status.os = os_info["PRETTY_NAME"]
    local arch_info
    arch_info = getGoArch(os_info["OPENWRT_ARCH"])
    local pkg_cmd
    if is_opkg_available() then
        pkg_cmd = "opkg"
    elseif is_apk_available() then
        pkg_cmd = "apk"
    else
        pkg_cmd = _("unknown")
    end
    status.pkg_cmd = pkg_cmd
    status.arch =  arch_info
    status.yacd_url = uci:get(service_name, "config", "yacd_url")
    status.last_log = get_last_log()

    -- Return status info in JSON format
    http.prepare_content("application/json")
    http.write_json(status)
end

--- Function: Load editor status info
function api_load_editor_status()
    local status = {}

    status.editor_file = uci:get(service_name, "config", "editor_file")
    status.editor_theme = uci:get(service_name, "config", "editor_theme") or "dracula"

    http.prepare_content("application/json")
    http.write_json(status)
end

--- Backup config file (easy quick restore)
function api_backup_config()
    local backup_dir="/etc/openproxy"

    -- Backup environment config file
    sys.call("cp /etc/config/openproxy "..backup_dir)
    local backup_cmd = ""     -- Use -r option to copy directory recursively
    local reader = ltn12_popen("tar -C " .. backup_dir .. " -cz . 2>/dev/null")

    http.header('Content-Disposition', 'attachment; filename="Backup-' .. service_name .. '-%s-%s-%s.tar.gz"' %
        {device_name, device_arh, os.date("%Y-%m-%d-%H-%M-%S")})

    http.prepare_content("application/x-targz")
    luci.ltn12.pump.all(reader, http.write)
end

--- Function: Get mihomo log content
function api_get_logs()
    local logs = ""
    if fs.access(mihomo_log) then
        -- Read last 500 lines to avoid overwhelming the browser
        logs = sys.exec("tail -n 500 " .. mihomo_log .. " 2>/dev/null")
    end
    
    http.prepare_content("application/json")
    http.write_json({
        status = 1000,
        logs = logs,
        message = "Logs retrieved successfully"
    })
end

--- Function: Clear mihomo logs
function api_clear_logs()
    if fs.access(mihomo_log) then
        fs.writefile(mihomo_log, "")
    end
    
    http.prepare_content("application/json")
    http.write_json({
        status = 1000,
        message = "Logs cleared successfully"
    })
end

