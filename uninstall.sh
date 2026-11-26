#!/bin/bash
# uninstall.sh: remove the VPN setup (firewall rules, services, commands, top-bar indicator).
#
# Kept: your VPN connections in NetworkManager, /etc/wireguard, your settings in /etc/vpn,
# and the groups novpn / vpnonly. MANUAL.md section 9 says how to remove those too.
#     cd ~/vpn-setup && ./uninstall.sh
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user, not as root; it uses sudo itself." >&2
    exit 1
fi

echo "==> DNS back to normal"
sudo rm -f /etc/systemd/resolved.conf.d/vpn.conf
# A restart (not a reload) so the resolver really forgets the routed domains; then
# NetworkManager hands it the VPNs' DNS settings again.
sudo systemctl restart systemd-resolved.service
sudo nmcli general reload dns-full || true

echo "==> Services and firewall rules"
sudo systemctl disable --now vpn-dns.service vpn-firewall.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/vpn-firewall.service /etc/systemd/system/vpn-dns.service
sudo systemctl daemon-reload

echo "==> Commands"
sudo rm -f /usr/local/bin/vpn /usr/local/bin/novpn /usr/local/bin/vpnonly
for n in novpn vpnonly; do
    if [ "$(readlink "$HOME/.local/bin/$n" 2>/dev/null)" = "/usr/local/bin/$n" ]; then
        rm -f "$HOME/.local/bin/$n"
    fi
done

if command -v selinuxenabled >/dev/null && selinuxenabled && sudo semodule -l | grep -qx vpn_dnsmasq; then
    echo "==> SELinux module"
    sudo semodule -r vpn_dnsmasq
fi

echo "==> Top-bar indicator"
gnome-extensions disable vpn-status@vpn-setup 2>/dev/null || true
rm -rf "$HOME/.local/share/gnome-shell/extensions/vpn-status@vpn-setup"

echo
echo "Removed. Your VPNs still work as plain NetworkManager connections."
echo "Remove a Steam launch option that uses novpn, or that game won't start."
