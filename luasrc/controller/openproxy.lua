module("luci.controller.openproxy", package.seeall)

local uci = require("luci.model.uci").cursor()
local http = require "luci.http"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local jsonc = require "luci.jsonc"

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
    entry({"admin", "services", service_name, "ipset_manager"}, template("openproxy/ipset_manager"), _("IP Sets"), page_index)
    page_index = page_index + 1
    entry({"admin", "services", service_name, "clients"}, cbi("openproxy/clients"), _("Clients"), page_index)
    page_index = page_index + 1
    entry({"admin", "services", service_name, "help"}, template("openproxy/help"), _("Help"), page_index)
    page_index = page_index + 1
    entry({"admin", "services", service_name, "logs"}, template("openproxy/logs"), _("Logs"), page_index)
    page_index = page_index + 1
    entry({"admin", "services", service_name, "update"}, template("openproxy/update"), _("Update"), page_index)

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
    entry({"admin", "services", service_name, "api", "update_ipset"}, call("api_update_ipset")).leaf = true
    entry({"admin", "services", service_name, "api", "check_update"}, call("api_check_update")).leaf = true
    entry({"admin", "services", service_name, "api", "perform_update"}, call("api_perform_update")).leaf = true
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
    local p_region = http.formvalue("region")
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
    if p_region then
        uci:set(service_name, "config", "region", p_region)
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
    status.region = uci:get(service_name, "config", "region") or "china"

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

--- Function: Update IP set from URL
function api_update_ipset()
    local url = http.formvalue("url")
    local region = http.formvalue("region")
    
    if not url or not region then
        http.prepare_content("application/json")
        http.write_json({
            status = 400,
            message = "Missing URL or region parameter"
        })
        return
    end
    
    -- Validate region
    if region ~= "iran" and region ~= "russia" and region ~= "china" then
        http.prepare_content("application/json")
        http.write_json({
            status = 400,
            message = "Invalid region. Must be: iran, russia, or china"
        })
        return
    end
    
    local temp_file = "/tmp/iplist_" .. region .. "_download.txt"
    local output_file = "/etc/openproxy/rules_nft/nftset_" .. (region == "china" and "all_cn" or region) .. "_ips.nft"
    
    -- Download the IP list
    local download_cmd = "wget -q -O " .. temp_file .. " '" .. url .. "' 2>&1"
    local result = sys.exec(download_cmd)
    
    if not fs.access(temp_file) then
        http.prepare_content("application/json")
        http.write_json({
            status = 500,
            message = "Failed to download IP list from URL"
        })
        return
    end
    
    -- Process the downloaded file
    local ipv4_list = {}
    local ipv6_list = {}
    
    for line in io.lines(temp_file) do
        line = trim(line)
        -- Skip empty lines and comments
        if line ~=  "" and not line:match("^#") and not line:match("^%s*$") then
            -- Skip private IP ranges
            if not line:match("^10%.") and not line:match("^172%.1[6-9]%.") and 
               not line:match("^172%.2[0-9]%.") and not line:match("^172%.3[01]%.") and
               not line:match("^192%.168%.") and not line:match("^127%.") then
                -- Check if IPv6 (contains :) or IPv4
                if line:match(":") then
                    table.insert(ipv6_list, line)
                else
                    table.insert(ipv4_list, line)
                end
            end
        end
    end
    
    -- Generate nftables file
    local ipv4_set_name = region .. "ipv4"
    local ipv6_set_name = region .. "ipv6"
    if region == "china" then
        ipv4_set_name = "cnipv4"
        ipv6_set_name = "cnipv6"
    end
    
    local nft_content = "#!/usr/sbin/nft -f\n"
    nft_content = nft_content .. "# Auto-generated on " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    nft_content = nft_content .. "# Source: " .. url .. "\n\n"
    nft_content = nft_content .. "table inet oproxy_tproxy {\n"
    nft_content = nft_content .. "    set " .. ipv4_set_name .. " {\n"
    nft_content = nft_content .. "        type ipv4_addr ;\n"
    nft_content = nft_content .. "        flags interval ;\n"
    nft_content = nft_content .. "        elements = { " .. table.concat(ipv4_list, ",") .. " }\n"
    nft_content = nft_content .. "    }\n"
    nft_content = nft_content .. "    set " .. ipv6_set_name .. " {\n"
    nft_content = nft_content .. "        type ipv6_addr ;\n"
    nft_content = nft_content .. "        flags interval ;\n"
    nft_content = nft_content .. "        elements = { " .. table.concat(ipv6_list, ",") .. " }\n"
    nft_content = nft_content .. "    }\n"
    nft_content = nft_content .. "    set local_ipv4 {\n"
    nft_content = nft_content .. "        type ipv4_addr ;\n"
    nft_content = nft_content .. "        flags interval ;\n"
    nft_content = nft_content .. "        elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 192.88.99.0/24, 192.168.0.0/16, 203.0.113.0/24, 224.0.0.0/4, 240.0.0.0-255.255.255.255 }\n"
    nft_content = nft_content .. "    }\n\n"
    nft_content = nft_content .. "    set local_ipv6 {\n"
    nft_content = nft_content .. "        type ipv6_addr ;\n"
    nft_content = nft_content .. "        flags interval ;\n"
    nft_content = nft_content .. "        elements = { ::/128, ::1/128, fc00::/7, fe80::/10, ff00::/8, ::ffff:0:0/96, ::ffff:0:0:0/96, 64:ff9b::/96, 100::/64, 2001::/32, 2001:20::/28, 2001:db8::/32, 2002::/16 }\n"
    nft_content = nft_content .. "    }\n\n"
    nft_content = nft_content .. "    set all_ipv6 {\n"
    nft_content = nft_content .. "        type ipv6_addr ;\n"
    nft_content = nft_content .. "        flags interval ;\n"
    nft_content = nft_content .. "        elements = { ::/0 }\n"
    nft_content = nft_content .. "    }\n\n"
    nft_content = nft_content .. "}\n"
    
    -- Write to output file
    fs.writefile(output_file, nft_content)
    
    -- Clean up temp file
    fs.unlink(temp_file)
    
    http.prepare_content("application/json")
    http.write_json({
        status = 1000,
        message = "IP set updated successfully",
        ipv4_count = #ipv4_list,
        ipv6_count = #ipv6_list,
        region = region,
        file = output_file
    })
end

--- Function: Check for updates
function api_check_update()
    local repo_url = "https://api.github.com/repos/parsamoh/luci-app-openproxy/releases"
    -- Use curl to fetch releases because it's more reliable for HTTPS
    local cmd = "curl -s -k -H 'User-Agent: luci-app-openproxy' " .. repo_url
    local content = sys.exec(cmd)
    
    if not content or content == "" then
        http.prepare_content("application/json")
        http.write_json({
            status = 500,
            message = "Failed to fetch releases from GitHub"
        })
        return
    end

    local releases = jsonc.parse(content)
    if not releases or type(releases) ~= "table" then
        http.prepare_content("application/json")
        http.write_json({
            status = 500,
            message = "Failed to parse GitHub response"
        })
        return
        return
    end

    -- Sort releases by published_at date descending
    table.sort(releases, function(a, b)
        local date_a = a.published_at or ""
        local date_b = b.published_at or ""
        return date_a > date_b
    end)

    local current_version = "Unknown"
    local stable_version = nil
    local beta_version = nil
    local stable_url = nil
    local beta_url = nil

    -- Get current version
    if is_opkg_available() then
        current_version = trim(sys.exec("opkg list-installed luci-app-openproxy | cut -d ' ' -f 3") or "Unknown")
    elseif is_apk_available() then
        current_version = trim(sys.exec("apk info -e -v luci-app-openproxy | sed 's/luci-app-openproxy-//'") or "Unknown")
    end

    -- Determine package extension
    local pkg_ext = is_apk_available() and ".apk" or ".ipk"

    for _, release in ipairs(releases) do
        local is_prerelease = release.prerelease
        local tag_name = release.tag_name
        local assets = release.assets
        local download_url = nil

        -- Find compatible asset
        if assets then
            for _, asset in ipairs(assets) do
                if asset.name:match("luci%-app%-openproxy.*%" .. pkg_ext .. "$") then
                    download_url = asset.browser_download_url
                    break
                end
            end
        end

        if download_url then
            if is_prerelease then
                 if not beta_version then
                    beta_version = tag_name
                    beta_url = download_url
                end
            else
                if not stable_version then
                    stable_version = tag_name
                    stable_url = download_url
                end
            end
        end

        if stable_version and beta_version then
            break
        end
    end

    http.prepare_content("application/json")
    http.write_json({
        status = 1000,
        current_version = current_version,
        stable_version = stable_version,
        stable_url = stable_url,
        beta_version = beta_version,
        beta_url = beta_url
    })
end

--- Function: Perform update
function api_perform_update()
    local url = http.formvalue("url")
    if not url then
        http.prepare_content("application/json")
        http.write_json({
            status = 400,
            message = "Missing URL parameter"
        })
        return
    end

    local pkg_ext = is_apk_available() and ".apk" or ".ipk"
    local temp_file = "/tmp/openproxy_update" .. pkg_ext
    local log = "Downloading " .. url .. "...\n"

    -- Download
    sys.exec("rm -f " .. temp_file)
    local download_cmd = "wget -O " .. temp_file .. " '" .. url .. "' 2>&1"
    log = log .. sys.exec(download_cmd)

    if not fs.access(temp_file) then
         http.prepare_content("application/json")
        http.write_json({
            status = 500,
            log = log .. "\nDownload failed."
        })
        return
    end

    log = log .. "\nInstalling...\n"
    local install_cmd = ""
    if is_opkg_available() then
        install_cmd = "opkg install " .. temp_file .. " --force-reinstall 2>&1"
    elseif is_apk_available() then
        install_cmd = "apk add --allow-untrusted " .. temp_file .. " 2>&1"
    end

    log = log .. sys.exec(install_cmd)
    
    -- Cleanup
    sys.exec("rm -f " .. temp_file)

    http.prepare_content("application/json")
    http.write_json({
        status = 1000,
        log = log
    })
end

