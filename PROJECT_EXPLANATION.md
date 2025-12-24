# Detailed Project Explanation: `luci-app-openproxy`

`luci-app-openproxy` is a high-performance Clash proxy plugin designed for the OpenWrt web interface (LuCI). It focuses on providing a simple yet powerful way to manage transparent proxying using Clash Meta (Mihomo).

## 📂 Core Directory Structure

The project follows the standard OpenWrt package structure:

*   **`luasrc/`**: The heart of the LuCI web interface.
    *   `controller/openproxy.lua`: Manage web requests, API endpoints for the UI, and service lifecycle (start/stop/restart).
    *   `model/cbi/openproxy/options.lua`: Defines the configuration forms and maps web inputs to UCI (Unified Configuration Interface) settings.
    *   `view/openproxy/`: LuCI templates (`.htm` files) for rendering the "Main", "Edit", and "Help" pages.
*   **`root/etc/config/openproxy`**: The UCI configuration file where all user settings are stored.
*   **`root/etc/init.d/openproxy`**: The service initialization script that manages the Clash process, firewall rules, and configuration generation.
*   **`root/etc/openproxy/`**: The application's data directory.
    *   `core/`: Contains the Clash (Mihomo) binary.
    *   `template/`: YAML templates used to generate the final `config.yaml` based on your UCI settings.
    *   `ui/`: Hosts the **YACD (Yet Another Clash Dashboard)** web interface for advanced Clash management.
    *   `rules_nft/`: `nftables` scripts for transparent proxying (handling the actual traffic redirection).
*   **`po/`**: Translation files for different languages (i18n).
*   **`Makefile`**: The build instructions for the OpenWrt SDK.

---

## ⚙️ How It Works

1.  **Configuration**: When you change settings in the LuCI web interface, they are saved to `/etc/config/openproxy`.
2.  **Service Startups**: When the service starts (via `/etc/init.d/openproxy`):
    *   It uses `yq` to merge your selected configuration template with your specific settings (proxies, rules, etc.) to generate `/etc/openproxy/config.yaml`.
    *   It configures **nftables** rules to redirect network traffic to the Clash ports (TPROXY for transparent proxying and DNS hijacking).
    *   It starts the Clash process using `procd` (OpenWrt's process manager), which ensures it stays running (respawn).
3.  **Traffic Handling**:
    *   **Transparent Proxy**: All traffic passing through the router is intercepted by `nftables` and forwarded to Clash.
    *   **DNS Hijacking**: DNS requests are redirected to Clash's built-in DNS server (or a custom one) to prevent DNS leaking and support features like Fake-IP.
4.  **Monitoring**: The LuCI interface polls the API provided by the controller to show if the service is "running" and displays the latest logs from `/tmp/openproxy.log`.

---

## 🔥 Key Technologies Used

*   **Clash Meta (Mihomo)**: The core proxy engine, support for advanced protocols and rule sets.
*   **nftables**: Modern Linux packet filtering framework used for high-performance traffic redirection.
*   **yq**: A portable command-line YAML processor used for dynamic configuration generation.
*   **LuCI / UCI**: The standard tools for OpenWrt web development and configuration management.
*   **YACD**: A beautiful third-party dashboard integrated directly into the plugin for a premium user experience.

---

## 🚀 Unique Features

*   **No TUN Mode**: By design, it avoids TUN mode to save CPU resources and maximize performance on lower-end router hardware.
*   **Native IPv6 Support**: Comprehensive support for IPv6 transparent proxying and DNS resolution.
*   **Online Editor**: Allows direct editing of configuration files from the browser with syntax highlighting.
*   **Minimalist Design**: Unlike many other proxy plugins, it aims for a clean and intuitive UI without overwhelming the user with unnecessary parameters.
