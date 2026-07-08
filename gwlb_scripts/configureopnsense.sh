#!/bin/sh

# ── Parameters ────────────────────────────────────────────────────────────────
# $1 = OPNScriptURI
# $2 = OpnVersion
# $3 = active_active_primary/active_active_secondary/single
# $4 = Trusted Nic Subnet
# $5 = Peer Server IP - Private IP Primary or Secondary Server
# $6 = vxlan local ip - vm trusted nic ip
# $7 = vxlan remote ip - gwlb frontend ip
# $8 = vxlan internal local port - 10800
# $9 = vxlan external local port - 10801
# $10 = vxlan internal identifier - 800 (800~1000)
# $11 = vxlan external identifier - 801 (800~1000)

OPN_SCRIPT_URI="$1"
OPN_VERSION="$2"
ROLE="$3"
TRUSTED_SUBNET="$4"
PEER_IP="$5"
VXLAN_LOCAL_IP="$6"
VXLAN_REMOTE_IP="$7"
VXLAN_INTERNAL_LOCAL_PORT="$8"
VXLAN_EXTERNAL_LOCAL_PORT="$9"
VXLAN_INTERNAL_ID="${10}"
VXLAN_EXTERNAL_ID="${11}"


# ── Logging ───────────────────────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ── Helper: Resolve trusted NIC gateway IP ────────────────────────────────────
# Uses python3 directly since the python symlink is created later in this script
fetch_gw_ip() {
    fetch -q "${OPN_SCRIPT_URI}get_nic_gw.py"
    PYTHON_BIN=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
    if [ -z "$PYTHON_BIN" ]; then
        echo "ERROR: No Python interpreter found to run get_nic_gw.py." >&2
        exit 1
    fi
    "$PYTHON_BIN" get_nic_gw.py "$TRUSTED_SUBNET"
}


# ── Apply OPNsense Configuration XML ─────────────────────────────────────────
log "Configuring OPNsense role: ${ROLE}"

# Check if Primary or Secondary Server to setup Firewal Sync
# Note: Firewall Sync should only be setup in the Primary Server
if [ "$ROLE" = "active_active_primary" ]; then
    fetch -q "${OPN_SCRIPT_URI}gwlb-config-active-active-primary.xml"
    GWIP=$(fetch_gw_ip)
    sed -i "" "s/yyy.yyy.yyy.yyy/${GWIP}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/xxx.xxx.xxx.xxx/${PEER_IP}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/lll.lll.lll.lll/${VXLAN_LOCAL_IP}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/rrr.rrr.rrr.rrr/${VXLAN_REMOTE_IP}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/zzz/${VXLAN_INTERNAL_ID}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/eeee/${VXLAN_INTERNAL_LOCAL_PORT}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/ccc/${VXLAN_EXTERNAL_ID}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/dddd/${VXLAN_EXTERNAL_LOCAL_PORT}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Primary<\/hostname>/" gwlb-config-active-active-primary.xml
    cp gwlb-config-active-active-primary.xml /usr/local/etc/config.xml
    
elif [ "$ROLE" = "active_active_secondary" ]; then
    fetch -q "${OPN_SCRIPT_URI}gwlb-config-active-active-secondary.xml"
    GWIP=$(fetch_gw_ip)
    sed -i "" "s/yyy.yyy.yyy.yyy/${GWIP}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/xxx.xxx.xxx.xxx/${PEER_IP}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/lll.lll.lll.lll/${VXLAN_LOCAL_IP}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/rrr.rrr.rrr.rrr/${VXLAN_REMOTE_IP}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/zzz/${VXLAN_INTERNAL_ID}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/eeee/${VXLAN_INTERNAL_LOCAL_PORT}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/ccc/${VXLAN_EXTERNAL_ID}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/dddd/${VXLAN_EXTERNAL_LOCAL_PORT}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Secondary<\/hostname>/" gwlb-config-active-active-secondary.xml
    cp gwlb-config-active-active-secondary.xml /usr/local/etc/config.xml

elif [ "$ROLE" = "single" ]; then
    fetch -q "${OPN_SCRIPT_URI}gwlb-config.xml"
    GWIP=$(fetch_gw_ip)
    sed -i "" "s/yyy.yyy.yyy.yyy/${GWIP}/" gwlb-config.xml
    sed -i "" "s/lll.lll.lll.lll/${VXLAN_LOCAL_IP}/" gwlb-config.xml
    sed -i "" "s/rrr.rrr.rrr.rrr/${VXLAN_REMOTE_IP}/" gwlb-config.xml
    sed -i "" "s/zzz/${VXLAN_INTERNAL_ID}/" gwlb-config.xml
    sed -i "" "s/eeee/${VXLAN_INTERNAL_LOCAL_PORT}/" gwlb-config.xml
    sed -i "" "s/ccc/${VXLAN_EXTERNAL_ID}/" gwlb-config.xml
    sed -i "" "s/dddd/${VXLAN_EXTERNAL_LOCAL_PORT}/" gwlb-config.xml
    cp gwlb-config.xml /usr/local/etc/config.xml
fi


# ── OPNsense Bootstrap ────────────────────────────────────────────────────────
log "Downloading OPNsense bootstrap script..."
fetch -q https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in

log "Enabling root SSH login..."
sed -i "" 's/#PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config

# Patch bootstrap:
#   - Disable set -e because pkg commands (unlock -a, delete -fa) return non-zero
#   - Delay reboot by 1 minute so the rest of this script can finish
log "Patching bootstrap script..."
sed -i "" "s/set -e/#set -e/g" opnsense-bootstrap.sh.in
sed -i "" "s/reboot/shutdown -r +1/g" opnsense-bootstrap.sh.in

log "Running OPNsense bootstrap (version: ${OPN_VERSION})..."
sh ./opnsense-bootstrap.sh.in -y -r "$OPN_VERSION"


# ── Azure WALinuxAgent ────────────────────────────────────────────────────────
log "Installing WALinuxAgent..."
# https://forum.opnsense.org/index.php?topic=40291.msg197657#msg197657
pkg install -y azure-agent

# Create /usr/local/bin/python symlink pointing at the installed python3 binary.
# Detected dynamically so it remains correct if the python3 minor version changes.
log "Configuring python symlink for waagent..."
PYTHON3_BIN=$(ls /usr/local/bin/python3.* 2>/dev/null | grep -vE '(\.py$|-config)' | sort -V | tail -1)
if [ -n "$PYTHON3_BIN" ] && [ ! -e /usr/local/bin/python ]; then
    ln -s "$PYTHON3_BIN" /usr/local/bin/python
    log "Symlink created: /usr/local/bin/python -> ${PYTHON3_BIN}"
fi

# ── Compatibility shims for legacy waagent extensions
# The legacy CustomScriptForLinux 1.5.4 handler code needs stdlib modules that
# were removed from modern Python:
#   - 'imp'   : removed in Python 3.12 (used by Utils/WAAgentUtil.py)
#   - 'crypt' : removed in Python 3.13 (imported by the bundled waagent script)
# Without these shims, extension disable/uninstall fails and Terraform
# deletion hangs with "polling after Delete: context deadline exceeded".
log "Installing compatibility shims for legacy waagent extensions..."
if [ -n "$PYTHON3_BIN" ]; then
    SITE_PKGS=$("$PYTHON3_BIN" -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null)
    if [ -n "$SITE_PKGS" ] && [ -d "$SITE_PKGS" ]; then
        # -- imp shim
        if "$PYTHON3_BIN" -c 'import imp' 2>/dev/null; then
            log "'imp' module already importable, shim not needed."
        else
            cat > "${SITE_PKGS}/imp.py" <<'EOF'
"""Minimal shim for the 'imp' module removed in Python 3.12.
 
Provides load_source(), which is what legacy Azure VM extension
handlers (e.g. Microsoft.OSTCExtensions.CustomScriptForLinux 1.5.x
Utils/WAAgentUtil.py) actually use.
"""
import importlib.machinery
import importlib.util
import sys
 
 
def load_source(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_file_location(name, path, loader=loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    loader.exec_module(module)
    return module
EOF
            log "Installed 'imp' shim at ${SITE_PKGS}/imp.py"
        fi
        # -- crypt shim
        if "$PYTHON3_BIN" -c 'import crypt' 2>/dev/null; then
            log "'crypt' module already importable, shim not needed."
        else
            cat > "${SITE_PKGS}/crypt.py" <<'EOF'
"""Minimal shim for the 'crypt' module removed in Python 3.13.
 
Delegates to the system crypt(3) via ctypes. Enough for legacy
waagent / Azure VM extension code paths.
"""
import ctypes
import ctypes.util
 
_lib = None
for _name in (ctypes.util.find_library("crypt"), ctypes.util.find_library("c")):
    if not _name:
        continue
    try:
        _cand = ctypes.CDLL(_name)
        _cand.crypt.restype = ctypes.c_char_p
        _cand.crypt.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        _lib = _cand
        break
    except (OSError, AttributeError):
        continue
 
 
def crypt(word, salt):
    if _lib is None:
        raise NotImplementedError("crypt(3) not available on this system")
    if isinstance(word, str):
        word = word.encode()
    if isinstance(salt, str):
        salt = salt.encode()
    result = _lib.crypt(word, salt)
    if result is None:
        raise OSError("crypt() failed")
    return result.decode()
EOF
            log "Installed 'crypt' shim at ${SITE_PKGS}/crypt.py"
        fi
    else
        log "WARNING: Could not locate site-packages; compatibility shims not installed."
    fi
fi

sed -i "" 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/' /etc/waagent.conf

log "Installing waagent actions configuration..."
fetch -q "${OPN_SCRIPT_URI}actions_waagent.conf"
cp actions_waagent.conf /usr/local/opnsense/service/conf/actions.d


# ── Additional Packages ───────────────────────────────────────────────────────
# bash  : required for Azure Custom Script Extension
# os-frr: FRRouting for dynamic routing support
log "Installing additional packages (bash, os-frr)..."
pkg install -y bash
pkg install -y os-frr


# ── Azure Route Fix ───────────────────────────────────────────────────────────
# Delete the 168.63.129.16 host route that Azure injects at boot; OPNsense
# uses a static ARP entry instead (see below) so the route is not needed and
# can interfere with traffic.
log "Adding startup hook to remove spurious Azure route..."
cat > /usr/local/etc/rc.syshook.d/start/22-remoteroute <<'EOL'
#!/bin/sh
route delete 168.63.129.16
EOL
chmod +x /usr/local/etc/rc.syshook.d/start/22-remoteroute


# ── Azure Load Balancer Probe / Internal VIP ──────────────────────────────────
# OPNsense must respond to ARP requests for 168.63.129.16 so that:
#   1. Azure health probes from the load balancer reach the VM
#   2. Azure platform services (IMDS, waagent) remain reachable
log "Configuring static ARP entry for Azure Internal VIP (168.63.129.16)..."
{
    echo "# Azure Internal VIP - required for LB health probes and platform services"
    echo 'static_arp_pairs="azvip"'
    echo 'static_arp_azvip="168.63.129.16 12:34:56:78:9a:bc"'
} >> /etc/rc.conf

service static_arp start
echo 'service static_arp start' >> /usr/local/etc/rc.syshook.d/start/20-freebsd


# ── WebGUI Certificate Renewal ────────────────────────────────────────────────
# One-time boot hook: renews the self-signed WebGUI certificate after OPNsense
# first boots, then removes itself so it does not run on subsequent reboots.
log "Setting up one-time WebGUI certificate renewal hook..."
cat > /usr/local/etc/rc.syshook.d/start/94-restartwebgui <<'EOL'
#!/bin/sh
configctl webgui restart renew
rm /usr/local/etc/rc.syshook.d/start/94-restartwebgui
EOL
chmod +x /usr/local/etc/rc.syshook.d/start/94-restartwebgui

log "OPNsense provisioning complete. System will reboot in approximately 1 minute."
