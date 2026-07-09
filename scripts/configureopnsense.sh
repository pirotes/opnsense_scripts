#!/bin/sh

# ── Parameters ────────────────────────────────────────────────────────────────
# $1 = OPNScriptURI
# $2 = OpnVersion
# $3 = active_active_primary/active_active_secondary/single
# $4 = Trusted Nic Subnet
# $5 = ELB VIP Address
# $6 = Peer Server IP - Private IP Primary or Secondary Server

OPN_SCRIPT_URI="$1"
OPN_VERSION="$2"
ROLE="$3"
TRUSTED_SUBNET="$4"
ELB_VIP="$5"
PEER_IP="$6"


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
    fetch -q "${OPN_SCRIPT_URI}config-active-active-primary.xml"
    GWIP=$(fetch_gw_ip)
    sed -i "" "s/yyy.yyy.yyy.yyy/${GWIP}/" config-active-active-primary.xml
    sed -i "" "s/www.www.www.www/${ELB_VIP}/" config-active-active-primary.xml
    sed -i "" "s/xxx.xxx.xxx.xxx/${PEER_IP}/" config-active-active-primary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Primary<\/hostname>/" config-active-active-primary.xml
    cp config-active-active-primary.xml /usr/local/etc/config.xml
    
elif [ "$ROLE" = "active_active_secondary" ]; then
    fetch -q "${OPN_SCRIPT_URI}config-active-active-secondary.xml"
    GWIP=$(fetch_gw_ip)
    sed -i "" "s/yyy.yyy.yyy.yyy/${GWIP}/" config-active-active-secondary.xml
    sed -i "" "s/www.www.www.www/${ELB_VIP}/" config-active-active-secondary.xml
    sed -i "" "s/xxx.xxx.xxx.xxx/${PEER_IP}/" config-active-active-secondary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Secondary<\/hostname>/" config-active-active-secondary.xml
    cp config-active-active-secondary.xml /usr/local/etc/config.xml
    
elif [ "$ROLE" = "single" ]; then
    fetch -q "${OPN_SCRIPT_URI}config.xml"
    GWIP=$(fetch_gw_ip)
    sed -i "" "s/yyy.yyy.yyy.yyy/${GWIP}/" config.xml
    cp config.xml /usr/local/etc/config.xml
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

## Neutralize legacy CustomScriptForLinux handler shim
# The 1.5.4 handler code is Python-2 era and breaks on modern Python
# (imp / crypt / distutils were all removed in Python 3.12~3.13) at
# disable/uninstall time, which makes Terraform extension deletion hang with
# "polling after Delete: context deadline exceeded". Since this script has
# already been executed by the time we reach this point, replace shim.sh with
# a no-op so any later -disable/-uninstall simply exits 0 and deletion succeeds.
#
# NOTE:
#   - Replace via mv (new inode), NOT in-place overwrite: this script is a
#     child of the currently running shim.sh, and truncating the file the
#     parent shell is still reading could corrupt it.
#   - After this, re-running/updating the SAME extension on this VM becomes a
#     no-op. That is fine for one-shot provisioning; a fresh VM deploy always
#     installs a fresh handler (which runs before this neutralization).
log "Neutralizing CustomScriptForLinux shim.sh for clean future deletion..."
for HANDLER_DIR in /var/lib/waagent/Microsoft.OSTCExtensions.CustomScriptForLinux-*; do
    [ -d "$HANDLER_DIR" ] || continue
    printf '#!/bin/sh\nexit 0\n' > "${HANDLER_DIR}/shim.sh.new"
    chmod 755 "${HANDLER_DIR}/shim.sh.new"
    cp -p "${HANDLER_DIR}/shim.sh" "${HANDLER_DIR}/shim.sh.bak.$(date +%Y%m%d%H%M%S)"
    mv "${HANDLER_DIR}/shim.sh.new" "${HANDLER_DIR}/shim.sh"
    log "Neutralized: ${HANDLER_DIR}/shim.sh"
done
##

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
