# Directory Description

This directory is used to store:
- file type proxy-provider: Reference configuration template template/proxy.yaml

Used to store custom configuration files. The configuration file editor will read all configuration files with the .yaml suffix in the current directory.

## proxy-provider Configuration

For a complete configuration example, please refer to the template/proxy.yaml file.
Proxy group configuration supports file formats:
- yaml format: Conventional Clash supported file format, supports vless/singbox and other regular types.
- uri format: One proxy node per line, convenient for user configuration.
- base64 format: Usually a single line base64 string, containing multiple URI format nodes, usually suitable for making subscription configurations.

