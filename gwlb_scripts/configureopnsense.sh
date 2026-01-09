#!/bin/sh

# Script Params
# $1 = OPNScriptURI
# $2 = OpnVersion
# $3 = active_active_primary/active_active_secondary/single
# $4 = Trusted Nic subnet GW IP
# $5 = Peer Server IP - Private IP Primary or Secondary Server
# $6 = vxlan local ip - vm trusted nic ip
# $7 = vxlan remote ip - gwlb frontend ip
# $8 = vxlan internal local port - 10800
# $9 = vxlan external local port - 10801
# $10 = vxlan internal identifier - 800 (800~1000)
# $11 = vxlan external identifier - 801 (800~1000)

# Check if Primary or Secondary Server to setup Firewal Sync
# Note: Firewall Sync should only be setup in the Primary Server
if [ "$3" = "active_active_primary" ]; then
    fetch $1gwlb-config-active-active-primary.xml
    sed -i "" "s/yyy.yyy.yyy.yyy/$4/" gwlb-config-active-active-primary.xml
    sed -i "" "s/xxx.xxx.xxx.xxx/$5/" gwlb-config-active-active-primary.xml
    sed -i "" "s/lll.lll.lll.lll/$6/" gwlb-config-active-active-primary.xml
    sed -i "" "s/rrr.rrr.rrr.rrr/$7/" gwlb-config-active-active-primary.xml
    sed -i "" "s/zzz/${10}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/eeee/$8/" gwlb-config-active-active-primary.xml
    sed -i "" "s/ccc/${11}/" gwlb-config-active-active-primary.xml
    sed -i "" "s/dddd/$9/" gwlb-config-active-active-primary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Primary<\/hostname>/" gwlb-config-active-active-primary.xml
    cp gwlb-config-active-active-primary.xml /usr/local/etc/config.xml
elif [ "$3" = "active_active_secondary" ]; then
    fetch $1gwlb-config-active-active-secondary.xml
    sed -i "" "s/yyy.yyy.yyy.yyy/$4/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/xxx.xxx.xxx.xxx/$5/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/lll.lll.lll.lll/$6/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/rrr.rrr.rrr.rrr/$7/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/zzz/${10}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/eeee/$8/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/ccc/${11}/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/dddd/$9/" gwlb-config-active-active-secondary.xml
    sed -i "" "s/<hostname>OPNsense<\/hostname>/<hostname>OPNsense-Secondary<\/hostname>/" gwlb-config-active-active-secondary.xml
    cp gwlb-config-active-active-secondary.xml /usr/local/etc/config.xml
elif [ "$3" = "single" ]; then
    fetch $1config.xml
    sed -i "" "s/yyy.yyy.yyy.yyy/$4/" config.xml
    sed -i "" "s/lll.lll.lll.lll/$6/" config.xml
    sed -i "" "s/rrr.rrr.rrr.rrr/$7/" config.xml
    sed -i "" "s/zzz/${10}/" config.xml
    sed -i "" "s/eeee/$8/" config.xml
    sed -i "" "s/ccc/${11}/" config.xml
    sed -i "" "s/dddd/$9/" config.xml
    cp config.xml /usr/local/etc/config.xml
fi

#Download OPNSense Bootstrap and Permit Root Remote Login
fetch https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in
sed -i "" 's/#PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config

#OPNSense
sed -i "" "s/set -e/#set -e/g" opnsense-bootstrap.sh.in
sed -i "" "s/reboot/shutdown -r +1/g" opnsense-bootstrap.sh.in
sh ./opnsense-bootstrap.sh.in -y -r "$2"

# WAagent
# https://forum.opnsense.org/index.php?topic=40291.msg197657#msg197657
pkg install -y azure-agent

# Fix waagent by replacing configuration settings
pyver=$(python3 -V | awk '{print $2}' | cut -d. -f1,2)
ln -s /usr/local/bin/python${pyver} /usr/local/bin/python
# sed -i "" 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/' /etc/waagent.conf
fetch $1actions_waagent.conf
cp actions_waagent.conf /usr/local/opnsense/service/conf/actions.d

# Installing bash - This is a requirement for Azure custom Script extension to run
pkg install -y bash
pkg install -y os-frr

# Remove wrong route at initialization
cat > /usr/local/etc/rc.syshook.d/start/22-remoteroute <<EOL
#!/bin/sh
route delete 168.63.129.16
EOL
chmod +x /usr/local/etc/rc.syshook.d/start/22-remoteroute

#VXLAN config
if [ "$3" = "active_active_primary" ]; then
    echo ifconfig hn0 mtu 4000 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig hn1 mtu 4000 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan0 down >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan0 vxlanlocal $6 vxlanremote $7 vxlanlocalport $9 vxlanremoteport $9 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan0 up >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan1 down >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan1 vxlanlocal $6 vxlanremote $7 vxlanlocalport $8 vxlanremoteport $8 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan1 up >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig bridge0 addm vxlan0 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig bridge0 addm vxlan1 >> /usr/local/etc/rc.syshook.d/start/25-azure
    chmod +x /usr/local/etc/rc.syshook.d/start/25-azure 
elif [ "$3" = "active_active_secondary" ]; then
    echo ifconfig hn0 mtu 4000 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig hn1 mtu 4000 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan0 down >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan0 vxlanlocal $6 vxlanremote $7 vxlanlocalport $9 vxlanremoteport $9 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan0 up >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan1 down >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan1 vxlanlocal $6 vxlanremote $7 vxlanlocalport $8 vxlanremoteport $8 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig vxlan1 up >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig bridge0 addm vxlan0 >> /usr/local/etc/rc.syshook.d/start/25-azure
    echo ifconfig bridge0 addm vxlan1 >> /usr/local/etc/rc.syshook.d/start/25-azure
    chmod +x /usr/local/etc/rc.syshook.d/start/25-azure
fi

#Adds support to LB probe from IP 168.63.129.16
#Add Azure VIP on Arp table
echo # Add Azure Internal VIP >> /etc/rc.conf
echo static_arp_pairs=\"azvip\" >>  /etc/rc.conf
echo static_arp_azvip=\"168.63.129.16 12:34:56:78:9a:bc\" >> /etc/rc.conf
# Makes arp effective
service static_arp start
# To survive boots adding to OPNsense Autorun/Bootup:
echo service static_arp start >> /usr/local/etc/rc.syshook.d/start/20-freebsd

# Reset WebGUI certificate
echo #\!/bin/sh >> /usr/local/etc/rc.syshook.d/start/94-restartwebgui
echo configctl webgui restart renew >> /usr/local/etc/rc.syshook.d/start/94-restartwebgui
echo rm /usr/local/etc/rc.syshook.d/start/94-restartwebgui >> /usr/local/etc/rc.syshook.d/start/94-restartwebgui
chmod +x /usr/local/etc/rc.syshook.d/start/94-restartwebgui
