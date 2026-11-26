# vpn-setup

Per-site and per-app VPN control for a Linux desktop (Fedora / GNOME), using WireGuard,
NetworkManager, nftables and dnsmasq. Built around one command: `vpn`.

- **Several WireGuard VPNs**, listed in one file. Switch with `vpn use "USA VPN"`.
  "Internet" VPNs (e.g. Proton) carry everything; "company" VPNs carry only their own servers.
- **Kill switch for chosen sites and apps.** Domains and IP ranges on the VPN-only list
  (e.g. ChatGPT, Claude) work only through a VPN. With no VPN up they're blocked, for every
  program, and their DNS lookups never leave the tunnel either. `vpn killswitch off` is
  the emergency exit.
- **Bypass list.** Domains and IP ranges that always skip the VPN (e.g. YouTube, Telegram,
  Gmail), for every program including Flatpak apps.
- **Game bypass.** `novpn <command>` (or the Steam launch option `novpn %command%`) runs a
  program outside the VPN.
- **Top-bar indicator.** GNOME shows the names of the VPNs that are up, and a warning while
  the kill switch is off.

## Quick start

```bash
git clone <this repo> ~/vpn-setup
sudo install -m 600 ~/Downloads/<your-wireguard>.conf /etc/wireguard/
cd ~/vpn-setup && ./install.sh
sudo nano /etc/vpn/vpns        # list your VPNs
vpn apply
vpn use "<your internet VPN>"
```

Then log out and back in once. Day to day:

```bash
vpn                            # status
vpn use "Dubai VPN"            # switch VPN
vpn off                        # plain internet
vpn killswitch off | on        # emergency switch
sudo nano /etc/vpn/vpn-only    # sites/apps that must use a VPN  → then: vpn apply
sudo nano /etc/vpn/bypass      # sites/apps that must skip it    → then: vpn apply
```

**Everything else is in [MANUAL.md](MANUAL.md)**: how each part works, step-by-step how-tos,
emergencies, troubleshooting, and the lessons learned while building it.

## Requirements

NetworkManager, systemd-resolved, nftables, dnsmasq built with `nftset`, python3. With
SELinux: checkpolicy and policycoreutils. For the indicator: GNOME Shell 48 or 49.
Tested on Fedora 42.

## Never commit or share

WireGuard `.conf` files and NetworkManager connection files contain **private keys**.
They live in `/etc/wireguard` and `/etc/NetworkManager`, never in this repository.
