#!/bin/bash
# install.sh: install or update the VPN setup described in MANUAL.md.
#
# Run it from this folder as your normal user; it asks for sudo when it needs it:
#     cd ~/vpn-setup && ./install.sh
#
# Safe to run again (e.g. after changing files in this folder). It never overwrites
# your own settings in /etc/vpn/vpns, /etc/vpn/vpn-only and /etc/vpn/bypass.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user, not as root; it uses sudo itself." >&2
    exit 1
fi
user=$(id -un)
step() { printf '\n==> %s\n' "$*"; }

step "Checking requirements"
missing=()
for cmd in nmcli nft dnsmasq python3 sg resolvectl systemctl; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if ((${#missing[@]})); then
    echo "Missing: ${missing[*]}" >&2
    echo "On Fedora: sudo dnf install NetworkManager nftables dnsmasq python3 shadow-utils systemd-resolved" >&2
    exit 1
fi
if ! dnsmasq --version | grep -qE '(^|[[:space:]])nftset([[:space:]]|$)'; then
    echo "This dnsmasq was built without nftset support, which the kill switch needs." >&2
    exit 1
fi

step "Groups: novpn (skip the VPN) and vpnonly (VPN only), with $user in both"
sudo groupadd -f novpn
sudo groupadd -f vpnonly
sudo usermod -aG novpn,vpnonly "$user"

step "Installing files"
sudo install -d -m 755 /etc/vpn /etc/vpn/generated
sudo install -m 644 etc/firewall.nft /etc/vpn/firewall.nft
[ -f /etc/vpn/vpns ]     || sudo install -m 644 etc/vpns.example /etc/vpn/vpns
[ -f /etc/vpn/vpn-only ] || sudo install -m 644 etc/vpn-only.example /etc/vpn/vpn-only
[ -f /etc/vpn/bypass ]   || sudo install -m 644 etc/bypass.example /etc/vpn/bypass
sudo install -m 755 bin/vpn /usr/local/bin/vpn
sudo install -m 755 bin/novpn /usr/local/bin/novpn
sudo ln -sfn novpn /usr/local/bin/vpnonly
sudo install -m 644 systemd/vpn-firewall.service systemd/vpn-dns.service /etc/systemd/system/
# If you keep personal copies of the launchers in ~/.local/bin, point them at the system
# ones, so a launch option like /home/<you>/.local/bin/novpn %command% keeps working.
for n in novpn vpnonly; do
    if [ -e "$HOME/.local/bin/$n" ] || [ -L "$HOME/.local/bin/$n" ]; then
        ln -sfn "/usr/local/bin/$n" "$HOME/.local/bin/$n"
    fi
done

if command -v selinuxenabled >/dev/null && selinuxenabled; then
    step "SELinux: allow dnsmasq to fill the firewall sets"
    for cmd in checkmodule semodule_package semodule; do
        command -v "$cmd" >/dev/null || { echo "Missing $cmd (Fedora: sudo dnf install checkpolicy policycoreutils)" >&2; exit 1; }
    done
    tmp=$(mktemp -d)
    checkmodule -M -m -o "$tmp/vpn_dnsmasq.mod" selinux/vpn_dnsmasq.te >/dev/null
    semodule_package -o "$tmp/vpn_dnsmasq.pp" -m "$tmp/vpn_dnsmasq.mod"
    sudo semodule -i "$tmp/vpn_dnsmasq.pp"
    rm -rf "$tmp"
fi

step "Services"
sudo systemctl daemon-reload
sudo systemctl enable --now vpn-firewall.service
sudo systemctl enable vpn-dns.service

step "Applying the settings in /etc/vpn"
sudo /usr/local/bin/vpn apply

step "Top-bar indicator (GNOME)"
ext=vpn-status@vpn-setup
if command -v gnome-extensions >/dev/null && command -v gsettings >/dev/null; then
    dest="$HOME/.local/share/gnome-shell/extensions/$ext"
    mkdir -p "$dest"
    cp "gnome-extension/$ext/"* "$dest/"
    # Add it to GNOME's list of enabled extensions (takes effect at the next login).
    python3 -I - "$ext" <<'PY'
import ast, subprocess, sys
new = sys.argv[1]
cur = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
                     capture_output=True, text=True, check=True).stdout.strip()
exts = list(ast.literal_eval(cur.removeprefix("@as ")))
if new not in exts:
    exts.append(new)
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", repr(exts)], check=True)
PY
    echo "Log out and back in once to load the top-bar indicator."
else
    echo "GNOME not found; skipped the top-bar indicator."
fi

step "Done"
/usr/local/bin/vpn status
