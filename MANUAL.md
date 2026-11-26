# VPN Setup Manual

This manual covers how this laptop handles its VPNs: what it does, how it works, how to change it, and how to rebuild it from scratch. Someone setting up their own machine the same way can follow it too.

**Everything lives in the folder `~/vpn-setup/`**: this manual, every source file, and an installer. Keep a copy of that folder somewhere safe (USB stick, cloud drive, git). If anything on the machine is ever lost, that folder plus your WireGuard files rebuild it.

> Keep this manual **offline**. The kill switch blocks claude.ai and Claude Code while no VPN is up, so when the VPN breaks you can't ask Claude for help. This file is your help.

Last updated: 2026-11-26

---

## Contents

1. [What this setup does](#1-what-this-setup-does)
2. [Example setup](#2-example-setup)
3. [Everyday commands](#3-everyday-commands)
4. [Where everything lives](#4-where-everything-lives)
5. [How it works](#5-how-it-works)
6. [How to…](#6-how-to)
7. [Emergencies](#7-emergencies)
8. [Troubleshooting](#8-troubleshooting)
9. [Install on a new machine, update, uninstall](#9-install-on-a-new-machine-update-uninstall)
10. [Sharing this setup safely](#10-sharing-this-setup-safely)
11. [Lessons learned](#11-lessons-learned-why-things-are-the-way-they-are)
12. [Glossary](#12-glossary)

---

## 1. What this setup does

Five features, all driven by three settings files and one command (`vpn`):

| Feature | What it does |
| --- | --- |
| **VPNs** | WireGuard VPNs are managed by NetworkManager, so the GNOME Quick Settings toggles and the terminal always agree. There are two kinds. An **internet** VPN (e.g. Proton) carries all traffic and DNS. A **company** VPN carries only the company's own server addresses. |
| **Top-bar indicator** | Shows the names of the VPNs that are up, e.g. `Dubai VPN · Work VPN`, without clicking. While the kill switch is off it also shows **⚠ kill switch off**. |
| **Game bypass** | Programs started with `novpn` (e.g. a Steam game) skip the VPN and use the normal connection, for lower ping. |
| **Bypass list** | Domains and IP ranges on the *bypass list* (YouTube, Telegram…) always skip the VPN, for **every** program, including Flatpak apps. Their DNS lookups skip it too, so services pick servers near your real location. |
| **Kill switch** | Domains and IP ranges on the *VPN-only list* (ChatGPT, Claude, Telegram…) only work through a VPN. With no VPN up, they don't work at all, for **every** program: Brave, Firefox, curl, the Telegram app, Claude Code. Their DNS lookups never leave the VPN either. |

What decides where a packet goes:

```
a program sends traffic
        │
        ▼
1. ROUTING: which way out?
   • to a company server (in the company VPN's AllowedIPs) ──► company VPN
   • destination on the VPN-only list ───────────────────────► never sent around the VPN
   • from a program started with `novpn` ────────────────────► normal connection (Wi-Fi)
   • destination on the bypass list ─────────────────────────► normal connection (Wi-Fi)
   • everything else ────────────────────────────────────────► internet VPN if one is up,
                                                                otherwise Wi-Fi
        │
        ▼
2. KILL SWITCH (only while it is ON):
   destination is on the VPN-only list, or the program was started with `vpnonly`,
   and it is NOT leaving through a VPN  ──► BLOCKED
```

The VPN-only list always wins:
- If a site is on both lists, it stays on the VPN.
- A `novpn` game that reaches a VPN-only site goes through the VPN (or is blocked if none is up). It's never leaked.

---

## 2. Example setup

The names used throughout this manual and in the example files. Your own setup is whatever you put in `/etc/vpn/vpns`, `/etc/vpn/vpn-only` and `/etc/vpn/bypass`; run `vpn` to see it.

| Item | Value |
| --- | --- |
| Machine | Fedora 42, GNOME 48 (Wayland), SELinux enforcing, NetworkManager + systemd-resolved |
| Internet VPN | **Dubai VPN**: a Proton VPN server in the UAE, DNS `10.2.0.1` |
| Company VPN | **Work VPN**: carries only the company's internal servers, starts at boot. Has no internet access of its own. |
| VPN-only list | ChatGPT (`chatgpt.com`), Claude (`anthropic.com`, `claude.ai`, `claude.com`) |
| Bypass list | YouTube, Gmail, LinkedIn, Telegram (its domains + its 14 official IP ranges) |
| Game bypass | A Steam game with the launch option `novpn %command%` |
| WireGuard originals | `/etc/wireguard/proton-ae-21.conf`, `/etc/wireguard/work.conf` (contain private keys) |

---

## 3. Everyday commands

```bash
vpn                          # same as `vpn status`: which VPNs are up, kill switch on/off
vpn use "Dubai VPN"          # switch to an internet VPN (it also becomes the one that starts at boot)
vpn off                      # no internet VPN: plain internet, now and after a reboot
vpn killswitch off           # emergency: VPN-only sites/apps work without a VPN (stays off until…)
vpn killswitch on            # …you turn it back on
vpn apply                    # apply your edits to /etc/vpn/vpns, vpn-only or bypass
vpn apply --dry-run          # show what `vpn apply` would do, change nothing
vpn help                     # list of commands

novpn <command>              # run something outside the VPN, e.g.  novpn curl https://ifconfig.me
vpnonly <command>            # run something that may only use a VPN (not for Flatpak apps, see 11.7)
```

- `vpn` asks for your sudo password when it needs it. `vpn status` doesn't.
- The GNOME Quick Settings toggles (top-right menu → VPN) do the same as `vpn use` / `vpn off` for the moment. Only `vpn use` changes which VPN starts at boot.
- Check your public IP: `curl https://ifconfig.me` (with the VPN) and `novpn curl https://ifconfig.me` (without it).

---

## 4. Where everything lives

**Your settings (edit these):**

| File | What it is |
| --- | --- |
| `/etc/vpn/vpns` | Your VPNs: name, WireGuard file, type. See [6.1](#61-add-a-new-vpn-eg-usa-germany-netherlands). |
| `/etc/vpn/vpn-only` | The kill-switch list: domains and IP ranges. See [6.5](#65-add-or-remove-a-site-or-app-on-the-vpn-only-list). |
| `/etc/vpn/bypass` | The bypass list: domains and IP ranges that always skip the VPN. See [6.7](#67-make-a-site-or-app-skip-the-vpn-bypass-list). |

**Managed for you (don't edit; `vpn apply` and the installer write these):**

| File | What it is |
| --- | --- |
| `/etc/vpn/killswitch-off` | Exists only while the kill switch is off |
| `/etc/vpn/firewall.nft` | Fixed part of the firewall (from `~/vpn-setup/etc/firewall.nft`) |
| `/etc/vpn/generated/rules.nft` | Generated part of the firewall: VPN interfaces, DNS servers, IP ranges of both lists, kill-switch rules |
| `/etc/vpn/generated/dnsmasq.conf` | Generated config of the private DNS server for the listed domains |
| `/etc/systemd/resolved.conf.d/vpn.conf` | Generated: sends DNS lookups for the listed domains (both lists) to that private DNS server |
| `/usr/local/bin/vpn` | The `vpn` command (Python) |
| `/usr/local/bin/novpn`, `/usr/local/bin/vpnonly` | The launchers (`vpnonly` is a link to `novpn`) |
| `~/.local/bin/novpn`, `~/.local/bin/vpnonly` | Links to the above, kept so older Steam launch options keep working |
| `/etc/systemd/system/vpn-firewall.service` | Loads the firewall at boot, before the network starts |
| `/etc/systemd/system/vpn-dns.service` | Runs the private DNS server (dnsmasq on `127.0.0.2`) |
| SELinux module `vpn_dnsmasq` | Allows dnsmasq to write to the firewall (see [11.6](#116-selinux-blocked-dnsmasq)) |
| `~/.local/share/gnome-shell/extensions/vpn-status@vpn-setup/` | The top-bar indicator |
| NetworkManager store `/etc/NetworkManager/system-connections/` | The VPN connections themselves, **with their private keys** |

**Groups:** `novpn` (programs that skip the VPN) and `vpnonly` (programs that may only use a VPN). Your user is a member of both.

**Source (keep and back up):** `~/vpn-setup/`

```
~/vpn-setup/
├── MANUAL.md                 this manual
├── install.sh                installs / updates everything
├── uninstall.sh              removes it again
├── bin/vpn                   the vpn command
├── bin/novpn                 the novpn / vpnonly launcher
├── etc/firewall.nft          fixed firewall part
├── etc/vpns.example          starting point for /etc/vpn/vpns
├── etc/vpn-only.example      starting point for /etc/vpn/vpn-only
├── etc/bypass.example        starting point for /etc/vpn/bypass
├── systemd/vpn-firewall.service
├── systemd/vpn-dns.service
├── selinux/vpn_dnsmasq.te    SELinux rule (source)
└── gnome-extension/vpn-status@vpn-setup/   top-bar indicator
```

---

## 5. How it works

### 5.1 VPNs in NetworkManager

Each VPN in `/etc/vpn/vpns` is a NetworkManager *WireGuard connection*. Its name is the `[name]` you gave it. `vpn apply` imports new ones from their `file =` and keeps their settings right:

- **`type = internet`**, e.g. Proton:
  - The WireGuard file has `AllowedIPs = 0.0.0.0/0, ::/0`, so the VPN takes all traffic. NetworkManager does this with policy routing (its own routing table plus `ip rule`s).
  - `ipv4.dns-search ~.` and `ipv4.dns-priority -50` (and the same for IPv6) mean *all* DNS lookups go to the VPN's DNS server, so no DNS leaks to your ISP.
  - It gets the routing rule `priority 100 fwmark 0x6e76 table 254` that skipping the VPN needs (5.3, 5.4).
  - Only one internet VPN is up at a time. `vpn use` turns the others off and marks the chosen one "connect automatically" so it also starts at boot.
- **`type = company`:**
  - Only the addresses in the file's `AllowedIPs` go through it (for a company VPN, typically a few internal server IPs).
  - Its DNS settings are cleared on purpose (see 11.1).
  - `autostart = yes` connects it at boot.

The connection's *interface name* comes from the file name at import time. `vpn apply` picks one from the VPN's name, e.g. `USA VPN` → `usa-vpn`. You never need to type it.

Once imported, NetworkManager keeps its own copy of the config, **including the private key**, in `/etc/NetworkManager/system-connections/`. The original file isn't read again.

Control from either side: GNOME Quick Settings, `vpn use/off`, or plain `nmcli connection up/down "<name>"`. They all talk to NetworkManager, so they stay in sync.

### 5.2 Top-bar indicator

A small GNOME Shell extension (`vpn-status@vpn-setup`):
- Every 3 seconds, it asks NetworkManager which WireGuard connections are active and shows their names joined by `·`.
- It also checks whether `/etc/vpn/killswitch-off` exists. If so, it adds a yellow **⚠ kill switch off**.
- It hides itself when there's nothing to show. GNOME's own VPN icon stays next to it.

### 5.3 Game bypass (`novpn`)

1. `novpn <command>` runs the command with the **group** `novpn` (using `sg`).
2. The firewall rule `meta skgid novpn meta mark set 0x6e76` puts an invisible *mark* on every packet from that group.
3. Because that rule sits in a *route* chain, the kernel picks the route again after marking. The routing rule `priority 100 fwmark 0x6e76 table 254` (on every internet VPN) sends marked packets to the **main** routing table, whose default route is Wi-Fi.
4. The program had already chosen the VPN's address as its source address. The rule `meta mark 0x6e76 … masquerade` rewrites it to the Wi-Fi address on the way out, so replies come back.

The proof it works is the counters going up in `sudo nft list chain inet vpnsplit mark_bypass`.

`sg` is a "setuid" program, so Linux strips variables like `LD_LIBRARY_PATH` and `LD_PRELOAD` as it runs. Steam games need them, so `novpn` saves the whole environment first and restores it before starting the program (see 11.4).

Name lookups (DNS) from a `novpn` program still go through the VPN. Only its connections skip it.

### 5.4 Bypass list

This uses the same mark and routing rule as the game bypass, but chooses packets by **destination** instead of by program. So it works for every program, including Flatpak apps (which can't use `novpn`, see 11.7):

1. **DNS.**
   - Lookups for bypass domains (and their subdomains) go to vpn-dns, the private DNS server on `127.0.0.2`, just like VPN-only domains.
   - vpn-dns asks **Cloudflare's public DNS (`1.1.1.1`, `1.0.0.1`) directly over Wi-Fi**: its own lookups to those two servers are marked too. YouTube then answers with servers near your real location, and bypass sites keep working when the VPN is down.
2. **IP sets.** Every address vpn-dns hands out for a bypass domain goes into the sets `bypass_v4/v6`. Ranges written in `/etc/vpn/bypass` go into `bypass_ranges_v4/v6`.
3. **Marking.** Packets to those addresses get mark `0x6e76`, so they take the normal route and are masqueraded, exactly like 5.3 steps 3–4.
4. **IPv4 only.** Your normal connection has no IPv6, but the VPN does. An IPv6 address would quietly send a bypass site through the VPN. So while the bypass list has domains, vpn-dns answers with IPv4 addresses only (`filter-AAAA`). This applies to VPN-only domains too, which is harmless: they work over IPv4 through the VPN.
5. **The VPN-only list wins.**
   - The first rules in the marking chain skip anything in the VPN-only sets, so those addresses are never sent around the VPN.
   - A domain on both lists is treated as VPN-only, and `vpn apply` warns about it.
   - Because both lists share one dnsmasq, the **most specific** domain wins. For example, `gemini.google.com` on the VPN-only list beats `google.com` on the bypass list.

The proof it works is the counters on the `bypass_…` lines growing in `sudo nft list chain inet vpnsplit mark_bypass` while you watch YouTube.

### 5.5 Kill switch

Two layers for **domains**, one for **IP ranges**, one for **programs**:

1. **DNS layer: lookups only through the VPN.**
   - `/etc/systemd/resolved.conf.d/vpn.conf` tells the system resolver (systemd-resolved): *lookups for `chatgpt.com`, `anthropic.com`, … (and all their subdomains) go to `127.0.0.2`*. A specific domain like `~chatgpt.com` beats the VPN's catch-all `~.`.
   - On `127.0.0.2` runs **vpn-dns** (dnsmasq). It answers only the listed domains. For VPN-only domains it asks *only* the internet VPNs' own DNS servers (Proton: `10.2.0.1`), which can only be reached through the tunnel. (Bypass domains go to public DNS instead, see 5.4.)
   - **VPN down → the lookup fails.** The name is never sent to your ISP.
2. **IP layer: block the addresses.**
   - Every address vpn-dns hands out is added to the firewall sets `vpnonly_v4` / `vpnonly_v6` (dnsmasq's `nftset=` option) *before* the answer reaches the program.
   - A firewall rule refuses traffic to those addresses unless it leaves through a VPN interface. This also catches addresses that a browser cached before the VPN dropped.
3. **IP ranges.** Some apps don't use DNS at all; Telegram connects to built-in addresses. Ranges written in `/etc/vpn/vpn-only` go straight into the sets `vpnonly_ranges_v4/v6`, with the same rule.
4. **Programs.** Anything started with `vpnonly <command>` runs with group `vpnonly`. Its traffic is refused unless it leaves through a VPN interface (or `lo`, so a local proxy still works).

"Through a VPN" means: out through the interface of **any VPN listed in `/etc/vpn/vpns`**, internet or company, or through `lo`.

**Kill switch OFF** (`vpn killswitch off`):
- creates `/etc/vpn/killswitch-off`
- removes all kill-switch rules
- empties the address sets
- removes the DNS steering

Everything works like a normal machine. It stays like that, even across reboots, until `vpn killswitch on`.

### 5.6 Boot order

1. `vpn-firewall.service` loads `/etc/vpn/firewall.nft` + `/etc/vpn/generated/rules.nft` **before** the network starts. So there's no moment at boot where VPN-only traffic could leak.
2. `vpn-dns.service` starts dnsmasq right after.
3. NetworkManager starts: Wi-Fi, then the company VPNs with `autostart = yes` and the internet VPN you last chose with `vpn use`.

---

## 6. How to…

### 6.1 Add a new VPN (e.g. USA, Germany, Netherlands)

1. **Get its WireGuard file.** For Proton VPN:
   1. Sign in at account.protonvpn.com and open **Downloads** → **WireGuard configuration**.
   2. Pick a device name, platform **GNU/Linux**, and a server (e.g. *US#12* or *DE#5*).
   3. Click **Create**, then download the `.conf` file.
2. **Store it safely.** It contains a private key:
   ```bash
   sudo install -m 600 ~/Downloads/US-FREE-12.conf /etc/wireguard/US-FREE-12.conf
   rm ~/Downloads/US-FREE-12.conf
   ```
3. **Add it to `/etc/vpn/vpns`** (`sudo nano /etc/vpn/vpns`):
   ```ini
   [USA VPN]
   file = /etc/wireguard/US-FREE-12.conf
   type = internet
   ```
4. **Apply:** run `vpn apply`. It imports the VPN (switched off) and adds it to the kill switch's list of VPNs. You should see `+ USA VPN: imported from …`.
5. **Use it:** run `vpn use "USA VPN"`. Dubai VPN goes off, USA VPN comes on, and USA VPN now starts at boot. The top bar shows `USA VPN · Work VPN`.

Switch back any time with `vpn use "Dubai VPN"`. The game bypass and kill switch work the same with any internet VPN in the list.

A VPN from another provider works the same way. Its DNS server is read from its own config. The name you choose can be anything, with spaces too. In commands, put it in quotes.

### 6.2 Switch VPN, or go without one

```bash
vpn use "Dubai VPN"     # switch (and make it the boot default)
vpn off                 # no internet VPN at all (company VPN stays)
vpn                     # check
```

With no internet VPN up and the kill switch **on**, VPN-only sites and apps are blocked. That's the point of it. Use `vpn killswitch off` if you need them anyway.

### 6.3 Remove a VPN

1. Delete its section from `/etc/vpn/vpns`.
2. Remove the connection: `nmcli connection delete "USA VPN"`.
3. Run `vpn apply`.
4. Optional: delete its file from `/etc/wireguard/`, and revoke the config in your VPN provider's dashboard.

If you only do step 1, `vpn apply` warns that the connection is still in NetworkManager but no longer counts as a VPN.

### 6.4 Replace a VPN's config (new keys, expired config)

```bash
nmcli connection delete "Dubai VPN"
sudo install -m 600 ~/Downloads/new.conf /etc/wireguard/proton-ae-21.conf   # or point file = at the new file
vpn apply                    # re-imports it
vpn use "Dubai VPN"
```

### 6.5 Add or remove a site or app on the VPN-only list

```bash
sudo nano /etc/vpn/vpn-only
vpn apply
```

- **A domain covers all its subdomains.** `openai.com` also covers `api.openai.com`, `platform.openai.com`, …
- **An IP or IP range** (`1.2.3.4`, `91.108.4.0/22`, `2001:b28:f23d::/48`) is for apps that connect to fixed addresses.
- **Removing** a line and running `vpn apply` un-blocks it completely. Applying empties the address sets, and they refill as things are looked up.
- **Don't add huge shared domains** like `google.com`, `googleapis.com`, `cloudflare.com`, `amazonaws.com`. While the VPN is down they'd break large parts of the internet (see 11.8).
- `#` starts a comment. Invalid lines are reported and skipped.

**Finding what an app or site uses:**
- `sudo resolvectl monitor` shows every name looked up, live. Start it, use the app or site, and note the domains that belong to it.
- `ss -tnp | grep -i <app>` shows the addresses an app is connected to right now.
- For apps with fixed addresses, look for an official list (Telegram: https://core.telegram.org/resources/cidr.txt).

### 6.6 Make a program skip the VPN

- **Steam game:** right-click it → **Properties** → **General** → **Launch Options**:
  ```
  novpn %command%
  ```
  Keep any game options after `%command%`, e.g. `novpn %command% -console`.
- **Anything from the terminal:** `novpn <command>`.
- **Check it:** while the game runs, `ps -o egroup= -C <process>` should print `novpn`, and the counters in `sudo nft list chain inet vpnsplit mark_bypass` should grow.

### 6.7 Make a site or app skip the VPN (bypass list)

```bash
sudo nano /etc/vpn/bypass
vpn apply
```

- The format is the same as the VPN-only list: one domain (covers its subdomains) or IP range per line. `#` starts a comment.
- It works for every program: browsers, Flatpak apps like Telegram, curl.
- Use it for things that are slow or region-locked through the VPN (video, games' web services, local banking…).
- **Find what a site uses:** run `sudo resolvectl monitor` while you use it. List all of the site's own domains, or parts of it stay on the VPN. For YouTube, the videos come from `googlevideo.com` and the images from `ytimg.com`.
- **Don't list huge shared domains** (`google.com`, `googleapis.com`, `cloudflare.com`, `amazonaws.com`), or half the internet skips the VPN. List the specific host instead: `youtubei.googleapis.com`, not `googleapis.com`.
- **Check it:** open the site, then `sudo nft list set inet vpnsplit bypass_v4` shows its addresses, and the `bypass_v4` counters in `sudo nft list chain inet vpnsplit mark_bypass` grow.
- **Removing** a line and running `vpn apply` sends it through the VPN again.

### 6.8 If the company VPN starts giving internet access

Change `type = company` to `type = internet` for it in `/etc/vpn/vpns` and run `vpn apply`. It then behaves like any internet VPN: `vpn use "Work VPN"`, its DNS, the bypass rule.

### 6.9 See what's happening

```bash
vpn                                         # overview
sudo nft list table inet vpnsplit           # all rules, with packet counters
sudo nft list set inet vpnsplit vpnonly_v4  # addresses currently blocked outside the VPN
sudo nft list set inet vpnsplit bypass_v4   # addresses currently sent around the VPN
ip rule                                     # routing rules (look for "fwmark 0x6e76")
resolvectl status                           # which DNS server serves what
systemctl status vpn-firewall vpn-dns       # the two services
journalctl -u vpn-dns -b                    # private DNS server log
```

---

## 7. Emergencies

**"My VPN is gone and I need ChatGPT or Claude now."**
```bash
vpn killswitch off
```
They work immediately over your normal connection. The top bar shows **⚠ kill switch off** until you run `vpn killswitch on`. This works offline; it only needs your sudo password.

**"Lookups for listed sites fail even with the VPN on"** (e.g. vpn-dns crashed). These commands remove just the DNS steering, so every name is looked up normally:
```bash
sudo rm /etc/systemd/resolved.conf.d/vpn.conf
sudo systemctl restart systemd-resolved
sudo nmcli general reload dns-full      # NetworkManager re-sends the VPN's DNS settings
```
Use `restart`, not `reload`. A reload doesn't forget domains (11.12). The next `vpn apply` (or `vpn killswitch on`) puts the steering back, so fix the cause first (see 8).

**"Turn the whole thing off for now":**
```bash
sudo rm -f /etc/systemd/resolved.conf.d/vpn.conf
sudo systemctl restart systemd-resolved
sudo nmcli general reload dns-full
sudo systemctl stop vpn-firewall        # also stops vpn-dns; no bypass, no kill switch
```
Back on: `sudo systemctl start vpn-firewall vpn-dns && vpn apply`. A reboot also brings it back.

**"No internet at all"**: see 8.1.

---

## 8. Troubleshooting

### 8.1 No internet at all
- Run `vpn`. Is an internet VPN up? Try `vpn off`. If the internet comes back, the VPN server is the problem. Try another one with `vpn use`.
- Does an IP work but not a name? Compare `ping -c1 1.1.1.1` with `ping -c1 google.com`. If only names fail, it's DNS: run `resolvectl status` and look for a VPN link with `~.` that is down. Also check that no **company** VPN has a DNS server (11.1).

### 8.2 A VPN-only site doesn't load even with the VPN up
- `systemctl status vpn-dns`: is it running?
  - If it says `Unable to initialize Netlink socket: Permission denied`, the SELinux module is missing. Re-run `~/vpn-setup/install.sh`, or see 11.6.
- `resolvectl query chatgpt.com` should return addresses.
- `sudo nft list set inet vpnsplit vpnonly_v4` should contain them after you open the site.

### 8.3 Claude Code or claude.ai can't connect (`ENOTFOUND api.anthropic.com`, connection errors)
That's the kill switch doing its job: no VPN is up. Run `vpn use "<name>"`, or `vpn killswitch off`.

### 8.4 A site that's *not* on the list breaks while the VPN is off
It probably shares an IP address with a listed site (common with Cloudflare, see 11.8). It works again when the VPN is up, or after `vpn apply`, which empties the address sets.

### 8.5 The game still goes through the VPN
- Check the launch option: `novpn %command%` (with `%command%`).
- While it runs: `ps -o egroup=,comm= -C <game process>` (e.g. `-C dota2`) should say `novpn`.
- `ip rule` should list `fwmark 0x6e76 lookup main`. If it doesn't, run `vpn apply` and reconnect the VPN.

### 8.6 A bypass site still goes through the VPN
- Is the domain listed? Look at `/etc/vpn/bypass`, and check `vpn apply` for "on both lists" warnings.
- Does it resolve through vpn-dns? `resolvectl query youtube.com` should list IPv4 addresses only, and `sudo nft list set inet vpnsplit bypass_v4` should contain them.
- The site may use more domains than you listed. Run `sudo resolvectl monitor` while loading it and add the missing ones.
- Browsers keep open connections and cached lookups for a short while. After `vpn apply`, reload the page or restart the browser.
- If the browser uses its own secure DNS, it skips vpn-dns completely (11.9).

### 8.7 A site stops working right after you removed it from a list
`resolvectl query <site>` says `REFUSED`. The resolver is still sending that name to vpn-dns, which no longer knows it. Check:
```bash
busctl get-property org.freedesktop.resolve1 /org/freedesktop/resolve1 org.freedesktop.resolve1.Manager Domains
```
If the removed domain is still listed, the resolver kept it from before (11.12). Running `vpn apply` restarts the resolver and clears it. On an old copy of `vpn`, use `sudo systemctl restart systemd-resolved && sudo nmcli general reload dns-full`.

### 8.8 The top bar shows nothing
- `gnome-extensions info vpn-status@vpn-setup` should show `State: ACTIVE`. If it doesn't, log out and back in once.
- Errors: `journalctl --user -b -o cat /usr/bin/gnome-shell | grep -i vpn-status`.

### 8.9 `vpn apply` fails
It checks everything before changing anything. If the firewall rules wouldn't load, it says so and keeps the old ones. Read the message: usually a bad line in `/etc/vpn/vpn-only` or `/etc/vpn/vpns`. Use `vpn apply --dry-run` to see what it would generate.

### 8.10 A service fails after copying files around
Copying a file with `mv` keeps its old SELinux label, and system services can then not read it ("Permission denied" even as root). Use `sudo install` (as the installer does), or fix the labels: `sudo restorecon -Rv /etc/vpn /etc/wireguard`. See 11.2.

---

## 9. Install on a new machine, update, uninstall

### 9.1 Requirements
- Linux with **NetworkManager**, **systemd-resolved**, **nftables**, **dnsmasq** (built with `nftset`), **python3**, `sg` (shadow-utils).
- Fedora 42 has all of these. Install anything missing with `sudo dnf install NetworkManager nftables dnsmasq python3`.
- With SELinux (Fedora): `checkpolicy` and `policycoreutils` to build the small SELinux module.
- For the top-bar indicator: GNOME Shell 48 or 49.

### 9.2 Install
1. Copy the `vpn-setup` folder into your home folder, e.g. `~/vpn-setup`.
2. Put your WireGuard files in `/etc/wireguard/` (`sudo install -m 600 <file> /etc/wireguard/`).
3. Run the installer as your normal user:
   ```bash
   cd ~/vpn-setup && ./install.sh
   ```
   It checks the requirements and creates the groups `novpn` and `vpnonly`. Then it installs the files, the SELinux module and the services, runs `vpn apply` and installs the top-bar indicator. It never overwrites an existing `/etc/vpn/vpns`, `/etc/vpn/vpn-only` or `/etc/vpn/bypass`.
4. Edit **`/etc/vpn/vpns`**: replace the examples with your VPNs and file paths (6.1). Then edit **`/etc/vpn/vpn-only`** (6.5) and **`/etc/vpn/bypass`** (6.7) to taste.
5. Run `vpn apply`, then `vpn use "<your internet VPN>"`.
6. Log out and back in once (for the top-bar indicator and the new groups).
7. Optional: set `novpn %command%` as the launch option of games that should skip the VPN.

If you used WireGuard before through `wg-quick` (`wg-quick@….service`), turn that off first: `sudo systemctl disable --now wg-quick@<name>`. Otherwise two programs fight over the same tunnel (11.3).

### 9.3 Update
After changing anything in `~/vpn-setup` (or getting a newer copy), run `./install.sh` again. It's safe to repeat.

### 9.4 Uninstall
```bash
cd ~/vpn-setup && ./uninstall.sh
```
This removes the services, firewall rules, commands, SELinux module and indicator. It keeps your VPN connections (they keep working as plain NetworkManager VPNs), `/etc/vpn`, `/etc/wireguard` and the groups.

Remove the `novpn` launch options from Steam games afterwards. To remove the rest too:
```bash
sudo rm -r /etc/vpn
sudo groupdel novpn; sudo groupdel vpnonly
```

---

## 10. Sharing this setup safely

**Fine to share:** the `~/vpn-setup` folder (`tar czf vpn-setup.tgz -C ~ vpn-setup`). It contains no keys or passwords.

**Never share:**
- **WireGuard `.conf` files** (`/etc/wireguard/*`). Each contains a **private key**: anyone with it can use your VPN as you.
- **NetworkManager connection files** (`/etc/NetworkManager/system-connections/*`). They hold the same keys.
- **Company details**: the company VPN's config and its server addresses.

The names in `etc/vpns.example` and in this manual are examples. Whoever uses this replaces them with their own (9.2 step 4).

If a key ever leaks, revoke that config in the VPN provider's dashboard (Proton: Downloads → WireGuard configuration → delete it) or ask the company admin for a new one. Then follow 6.4.

---

## 11. Lessons learned (why things are the way they are)

These are the problems hit while building this. Each one explains a design choice.

### 11.1 A DNS line in the company config killed the internet
The company WireGuard file came with `DNS = 1.1.1.1`. When it was up, the system sent **all** name lookups through the company tunnel, which has no internet access. Every lookup failed: it looked like "no internet", although only names were broken (IPs worked).

**Rule:** a company (split) VPN must not have DNS settings. `vpn apply` clears them for `type = company`.

### 11.2 `mv` + SELinux = "Permission denied" for root
A config moved with `mv` from the home folder kept its "home folder" SELinux label, and the systemd service could not read it. Terminal `sudo` worked; the boot service didn't.

**Fix:** `sudo restorecon -Rv <dir>`. **Rule:** put files in system folders with `sudo install`, never `mv`.

### 11.3 Two managers for one tunnel get out of sync
At first the tunnels ran through `wg-quick` (systemd) while GNOME showed them through NetworkManager. Switching one off in Quick Settings stripped its addresses, but systemd still thought it was up: a half-broken tunnel.

**Rule:** NetworkManager alone owns the VPNs. Control them with Quick Settings, `vpn`, or `nmcli`, all of which talk to NetworkManager.

### 11.4 `sg` strips environment variables
Switching group with `sg` (setuid) makes Linux drop `LD_PRELOAD`, `LD_LIBRARY_PATH`, `TMPDIR`, etc. Steam games need them. `novpn` saves the full environment before `sg` and restores it after.

### 11.5 Policy routing needs a mark, a route chain and masquerade
Marking packets isn't enough: the kernel must redo the routing decision. That needs a `type route` chain plus an `ip rule` for the mark. The source address must also be rewritten (masquerade), because the program already picked the VPN's address.

### 11.6 SELinux blocked dnsmasq
dnsmasq (vpn-dns) failed at start with `Unable to initialize Netlink socket: Permission denied`. The audit log showed `avc: denied { create } … dnsmasq_t … tclass=netlink_netfilter_socket`. Fedora's policy doesn't let dnsmasq write firewall sets.

**Fix:** the small module `selinux/vpn_dnsmasq.te`, which allows exactly that. To check for denials: `sudo ausearch -m avc -ts recent`.

### 11.7 Don't run Flatpak apps under another group
Starting the Flatpak Telegram with `vpnonly` failed. Flatpak's *document portal* (`/run/user/<uid>/doc`, used for opening and sending files) refuses access from a different group. Turning the portal off would break file sharing.

**Rule:** cover Flatpak apps by their **IP ranges or domains** in `/etc/vpn/vpn-only`, not with `vpnonly`.

### 11.8 Shared IP addresses (Cloudflare)
Many sites share the same addresses. chatgpt.com sits on Cloudflare IPs that other sites use too. While the VPN is **down**, those other sites are blocked as well. With the VPN up, nothing is affected.

That's why huge shared domains don't belong on the list.

### 11.9 Browsers with their own DNS
If a browser uses its own "secure DNS" (DNS-over-HTTPS), its lookups skip the system resolver, and the DNS layer can't see them. Brave's "automatic" mode doesn't kick in with this setup (it only upgrades known public DNS servers), so nothing was changed. If a browser is set to a fixed secure DNS provider, turn that off:
- Brave/Chrome: Settings → Privacy and security → Security → Use secure DNS
- Firefox: Settings → Privacy & Security → DNS over HTTPS

### 11.10 IPv6 would quietly undo the bypass
The VPN offers IPv6, the home connection doesn't, and browsers prefer IPv6. A bypass site that resolved to an IPv6 address would go through the VPN anyway, or stall when sent around it. Hence `filter-AAAA` in vpn-dns while the bypass list has domains (5.4).

### 11.11 Moving Telegram from the kill switch to the bypass list
At first Telegram was on the VPN-only list. Later the wish was the opposite: Telegram should never use the VPN. Its IP ranges work on either list, because the firewall acts on destinations, not on the app. That's why the bypass list takes IP ranges too, and why a Flatpak app needs no wrapper.

### 11.12 A resolver *reload* only ever adds domains
Gmail was taken off the bypass list and `vpn apply` was run, and Gmail stopped working: `REFUSED`. The config file was right, but the resolver's live list still had `mail.google.com`, `gmail.com` and `accounts.google.com`. So it still sent them to vpn-dns, which no longer knew them.

The cause: `systemctl reload systemd-resolved` re-reads the config and adds new routing domains, but never drops ones that were removed. It only showed up the first time something was *removed* from a list.

**Fix:** `vpn apply` now **restarts** the resolver. A restart also forgets the DNS settings NetworkManager gave it for each connection, so it then runs `nmcli general reload dns-full` to have NetworkManager send them again. It also checks that every running internet VPN got its DNS server back.

### 11.13 The helper is behind the kill switch
Claude Code and claude.ai are on the VPN-only list. When the VPN is down, the AI assistant that helped build this can't be reached. Hence this offline manual, and `vpn killswitch off` as the way out.

---

## 12. Glossary

| Term | Meaning |
| --- | --- |
| **WireGuard** | The VPN protocol. A `.conf` file has an `[Interface]` (your private key, your VPN address, DNS) and a `[Peer]` (server's public key, `Endpoint`, `AllowedIPs`). |
| **AllowedIPs** | Which destination addresses go through that tunnel. `0.0.0.0/0, ::/0` = everything (internet VPN); a few addresses = split (company VPN). |
| **NetworkManager / nmcli** | The service that manages all network connections, and its command-line tool. GNOME's Quick Settings use it. |
| **systemd-resolved / resolvectl** | The system's DNS resolver (`127.0.0.53`). It can send different domains to different DNS servers. `~.` = "all domains". |
| **dnsmasq** | A small DNS server. Here it runs as `vpn-dns` on `127.0.0.2` and serves only the VPN-only domains. |
| **nftables / nft** | Linux's firewall. All rules of this setup are in one table: `inet vpnsplit`. |
| **mark / fwmark** | An invisible tag on a packet (`0x6e76` here) that routing rules can act on. |
| **ip rule / policy routing** | Rules that choose *which routing table* to use, e.g. "packets marked 0x6e76 use the main table". |
| **masquerade** | Rewriting a packet's source address to the outgoing interface's address. |
| **SELinux** | Fedora's mandatory access control. It can deny things even to root. `ausearch -m avc` shows its denials. |
| **Kill switch** | Blocking chosen traffic whenever it would leave without a VPN. |
| **Split tunneling** | Sending only some traffic through a VPN (company VPN), or letting some skip it (game bypass). |
