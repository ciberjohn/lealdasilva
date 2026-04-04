# motd-improver

Three Bash scripts that replace the default Linux MOTD with a clean, colour-coded banner displaying real system intelligence: hostname (ASCII art via `figlet`), date/time, uptime, load average, live memory breakdown, and current weather via [wttr.in](https://wttr.in).

## Scripts

| Script | Purpose | Distro support |
|---|---|---|
| `setup-motd.sh` | Simple one-shot installer | Ubuntu/Debian only |
| `update-motd.sh` | Updater with memory + weather | Ubuntu/Debian only |
| `install-motd.sh` | Universal installer (recommended) | Debian/Ubuntu, RHEL/Rocky/AlmaLinux, Fedora, Arch, openSUSE, Alpine |

## Quick install

```bash
sudo bash install-motd.sh
```

You will be prompted for a weather location (e.g. `London,UK`), which is validated against wttr.in before installation proceeds.

## Requirements

- `curl` and `figlet` (installed automatically if missing)
- Root / sudo access

## What you get

```
   _____                          
  / ___/___  ______   _____  _____
  \__ \/ _ \/ ___/ | / / _ \/ ___/
 ___/ /  __/ /   | |/ /  __/ /    
/____/\___/_/    |___/\___/_/     

  ────────────────────────────────────────────────────────────────────────
  Date             Friday, 04 April 2026
  Time             14:32:07 BST
  Uptime           3 days, 2 hours, 14 minutes
  Load average     0.12, 0.08, 0.05  (4 CPU cores)
  Hostname         server.example.com
  Memory           Used: 42%  Free: 8%  Cached: 38%  Committed: 61%  Swap: 0%
  Weather          Mountain Ash, Wales: ⛅ +12°C
  ────────────────────────────────────────────────────────────────────────
```

## Notes

- Weather is cached for 30 minutes in `/var/cache/motd-weather` to avoid hammering wttr.in on every login.
- On Debian/Ubuntu, delivery is via `/etc/update-motd.d/` and PAM. On other distros, a cron job regenerates `/etc/motd` every minute.
- To change your weather location after install, edit the `wttr.in` URL in `/usr/local/bin/generate-motd`.
