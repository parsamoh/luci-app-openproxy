import os
import subprocess

# Configuration
ROUTER_IP = "192.168.10.1"
ROUTER_USER = "root"

def run_command(cmd):
    # print(f"Running: {cmd}")
    subprocess.run(cmd, shell=True, check=True)

def copy_directory_recursive(local_base, remote_base):
    if not os.path.exists(local_base):
        print(f"Directory not found: {local_base}")
        return

    print(f"Deploying {local_base} -> {remote_base}")
    for root, dirs, files in os.walk(local_base):
        for file in files:
            local_path = os.path.join(root, file)
            # Calculate relative path from local_base
            rel_path = os.path.relpath(local_path, local_base)
            remote_path = os.path.join(remote_base, rel_path)
            
            # Ensure proper separators
            remote_path = remote_path.replace("\\", "/")
            
            # print(f"  {local_path} -> {remote_path}")
            cmd = f"scp {local_path} {ROUTER_USER}@{ROUTER_IP}:{remote_path}"
            
            try:
                run_command(cmd)
            except subprocess.CalledProcessError:
                print(f"Failed to copy {local_path}")

def deploy():
    print(f"Starting full deployment to {ROUTER_USER}@{ROUTER_IP}...")
    
    # 1. Deploy root/* to /
    copy_directory_recursive("root", "/")
    
    # 2. Deploy luasrc/* to /usr/lib/lua/luci/
    copy_directory_recursive("luasrc", "/usr/lib/lua/luci")
    
    # 3. Post-install actions
    print("Setting permissions and restarting...")
    cmds = [
        "chmod +x /etc/init.d/openproxy",
        "rm -rf /tmp/luci-modulecache/*",
        "/etc/init.d/openproxy restart"
    ]
    
    for cmd in cmds:
        print(f"  Exec: {cmd}")
        run_command(f"ssh {ROUTER_USER}@{ROUTER_IP} '{cmd}'")
        
    print("Deployment completed successfully!")

if __name__ == "__main__":
    deploy()
