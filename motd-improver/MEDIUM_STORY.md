# Stop Tolerating Your Server's Ugly Login Screen

> Three Bash scripts that replace Ubuntu's noisy, useless MOTD with a sharp, colour-coded banner showing real system intelligence — and work on every major Linux distro.

---

Every time you SSH into a server, Linux presents you with a Message of the Day. On a stock Ubuntu install, that message is a wall of promotional noise: a stale kernel hint, an advertisement for Ubuntu Pro, a landscape-sysinfo block that takes three seconds to render, and a helpfully useless line telling you there are 47 packages to upgrade — the same 47 it told you about last week.

Nobody reads it. Nobody acts on it. It's just friction between you and the shell prompt.

I got fed up with it and spent a weekend fixing it properly. What I built — three Bash scripts under the `motd-improver` project — replaces the whole lot with a clean, colour-coded banner that tells you things you actually care about the moment you log in.

Here is what that looks like.

---

## What a Useful MOTD Actually Looks Like

```
   ___  ___  ___  _  __ ____  _____
  / _ \/ _ \/ _ \| |/ // __/ / ___/
 / ___/ , _/ ___/|   /_\ \  / /__
/_/  /_/|_/_/   /_/|_//___/  \___/

  ──────────────────────────────────────────────────────────────────────────
  Date              Saturday, 04 April 2026
  Time              09:14:32 BST
  Uptime            3 days, 14 hours, 22 minutes
  Load Average      0.42, 0.38, 0.31
  CPU Cores         8

  ──────────────────────────────────────────────────────────────────────────
  Mem Used          34%      Mem Free         12%
  Cached            54%      Committed        61%
  Swap              0%

  ──────────────────────────────────────────────────────────────────────────
  Weather           London, UK: ⛅  +9°C
  ──────────────────────────────────────────────────────────────────────────
```

The hostname is rendered in ASCII art via `figlet` (with a Unicode box-drawing fallback if `figlet` is not installed). Everything is colour-coded with ANSI sequences — cyan for the banner, yellow for labels, white for values, dim for the dividers. It loads in under a second.

That is what a login screen should look like.

---

## The Problem With the Default Ubuntu MOTD

Ubuntu's `update-motd` framework runs a collection of scripts from `/etc/update-motd.d/` on every login. Out of the box, this includes:

- `10-help-text` — tells you how to get help with Ubuntu. Every. Single. Login.
- `50-landscape-sysinfo` — fetches system stats but takes an age to render on a loaded box, and the output is ugly.
- `50-motd-news` — phones home to Canonical to fetch "news" and advertising. On a server. That you own.
- `80-livepatch` — Livepatch status, whether you use it or not.

None of this is useful in practice. Worse, the framework itself is fragile: system updates occasionally clobber `/etc/pam.d/sshd` in a way that silently disables dynamic MOTD entirely, so you end up with a blank login screen and no idea why.

The right fix is not to edit these scripts by hand. The right fix is to replace the whole mechanism cleanly and surgically.

---

## Three Scripts, One Goal

The project ships three scripts. They represent an evolution from quick proof-of-concept to production-grade installer, and you pick whichever fits your situation.

### `setup-motd.sh` — The Original

The first script is the simplest. It runs as root on Ubuntu, installs `figlet` via `apt-get`, backs up the existing `00-header`, and writes a new one. It strips execute permissions from the noisy default scripts (`landscape-sysinfo`, `motd-news`, `help-text`) without deleting them — a clean, reversible approach.

The MOTD generator itself is written into `/etc/update-motd.d/00-header` via a heredoc with a **single-quoted delimiter**:

```bash
cat > "${TARGET}" << 'MOTD_SCRIPT'
#!/bin/bash
DATE=$(date '+%A, %d %B %Y')
HOST=$(hostname -s)
# ... rest of generator ...
MOTD_SCRIPT
```

The single-quoted `'MOTD_SCRIPT'` delimiter is critical. It tells Bash to treat the entire heredoc body as a literal string — no variable expansion, no command substitution. The `$(date ...)` and `$(hostname -s)` calls inside are written verbatim to the target file, where they will expand at runtime on every login, not at install time. Get this wrong and your banner will show the date your server was built, forever.

### `update-motd.sh` — Memory and Weather

The second script adds the two most useful signals: a detailed memory breakdown and live weather.

Memory is parsed from `/proc/meminfo` in a single `awk` pass — nine values extracted in one read, no repeated `grep` calls, no unnecessary subprocesses:

```bash
read -r MEM_TOTAL MEM_FREE MEM_AVAIL BUFFERS CACHED SWAP_TOTAL SWAP_FREE COMMIT_AS COMMIT_LIMIT <<< \
    $(awk '/^MemTotal:/{mt=$2} /^MemFree:/{mf=$2} /^MemAvailable:/{ma=$2}
           /^Buffers:/{bu=$2} /^Cached:/{ca=$2}
           /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
           /^Committed_AS:/{cas=$2} /^CommitLimit:/{cl=$2}
           END{print mt,mf,ma,bu,ca,st,sf,cas,cl}' /proc/meminfo)
```

One detail worth highlighting: the "mem used" percentage is calculated against `MemAvailable`, not `MemFree`. On a healthy Linux server, `MemFree` will look alarming — the kernel fills spare RAM with page cache as a performance optimisation. `MemAvailable` is the kernel's own estimate of how much RAM can actually be reclaimed for new allocations. That is the number you want.

The commit percentage (`Committed_AS / CommitLimit`) is equally important and almost never shown on default dashboards. It represents virtual memory pressure — a value consistently above 80–90% means you are approaching the point where new allocations will fail even if physical RAM looks fine. Useful early warning for capacity planning.

Weather comes from `wttr.in` with a hardcoded location and tight timeouts:

```bash
WEATHER=$(curl -s --connect-timeout 4 --max-time 6 "wttr.in/London,UK?format=3" 2>/dev/null)
```

The `?format=3` flag requests the compact single-line format: `London, UK: ⛅  +9°C`. Four-second connection timeout, six-second hard cap. If `wttr.in` is unreachable, the field shows `(unavailable)` rather than breaking the layout.

---

## The Production Installer: `install-motd.sh`

This is the script you actually want to run in any real environment.

### It Knows What OS It Is Running On

The installer sources `/etc/os-release` and maps the distribution to one of six OS families:

```bash
source /etc/os-release
case "${ID}" in
    ubuntu|debian|raspbian|linuxmint|pop|elementary|kali|parrot) OS_FAMILY="debian" ;;
    rhel|centos|rocky|almalinux|ol|scientific)                    OS_FAMILY="rhel"   ;;
    fedora)                                                        OS_FAMILY="fedora" ;;
    arch|manjaro|endeavouros|garuda)                               OS_FAMILY="arch"   ;;
    opensuse*|sles)                                                OS_FAMILY="suse"   ;;
    alpine)                                                        OS_FAMILY="alpine" ;;
esac
```

If the primary `ID` match fails — because you are running some derivative that is not in the list — there is a fallback to `ID_LIKE`. Linux Mint sets `ID_LIKE="ubuntu debian"`, for example. This makes the detection forward-compatible with new derivatives without requiring code changes every time someone forks Debian.

Package manager detection is handled separately, by binary presence rather than OS assumption:

```bash
if   command -v apt-get  &>/dev/null; then PKG_MGR="apt"
elif command -v dnf      &>/dev/null; then PKG_MGR="dnf"
elif command -v yum      &>/dev/null; then PKG_MGR="yum"
elif command -v pacman   &>/dev/null; then PKG_MGR="pacman"
elif command -v zypper   &>/dev/null; then PKG_MGR="zypper"
elif command -v apk      &>/dev/null; then PKG_MGR="apk"
fi
```

This decoupling matters. On an RHEL system where `dnf` is present but `yum` is a compatibility symlink, the detection picks the right tool regardless of what the OS family mapping says.

### It Validates Your Weather Location Before Installing

Rather than blindly writing a location string into the generator and leaving you to discover at login time that `wttr.in` does not recognise it, the installer prompts you and validates the location live:

```bash
read -rp "Enter weather location (e.g. London,UK): " WEATHER_LOC
ENCODED_LOC=$(urlencode "${WEATHER_LOC}")
TEST_RESPONSE=$(curl -s --connect-timeout 5 --max-time 8 \
    "wttr.in/${ENCODED_LOC}?format=3" 2>/dev/null)

if [[ -z "${TEST_RESPONSE}" ]]; then
    warn "Could not reach wttr.in — weather will show as unavailable"
elif echo "${TEST_RESPONSE}" | grep -qi "unknown location\|sorry\|error"; then
    warn "wttr.in did not recognise '${WEATHER_LOC}' — weather may be inaccurate"
else
    ok "Weather location validated: ${TEST_RESPONSE}"
fi
```

`wttr.in` returns human-readable error text rather than HTTP error codes for unknown locations, so a plain `grep` on known error phrases catches mistyped locations. If the network is down, the installer continues with a warning — weather is a nice-to-have, not a critical dependency.

The `urlencode()` function is pure Bash — no `python3`, no `perl`, no `jq` dependency. It handles the character-by-character encoding itself. Spaces become `+`; everything else gets percent-encoded.

### It Handles PAM on Debian/Ubuntu

On Debian-family systems, the installer writes a minimal wrapper script to `/etc/update-motd.d/00-custom` that simply calls the generator. The actual generator lives at `/usr/local/bin/generate-motd` and can be tested, updated, or called independently without touching the PAM layer.

More importantly, it repairs a common Ubuntu breakage where system updates silently disable dynamic MOTD by removing or commenting out the `pam_motd.so` line in `/etc/pam.d/sshd`:

```bash
if ! grep -q "pam_motd.so.*motd=/run/motd.dynamic" /etc/pam.d/sshd 2>/dev/null; then
    echo "session optional pam_motd.so motd=/run/motd.dynamic noupdate" >> /etc/pam.d/sshd
fi
```

The `motd=/run/motd.dynamic` parameter points PAM at the dynamically-generated file. The `noupdate` flag tells PAM to display it without trying to regenerate it — that is the `update-motd` framework's job. The check is idempotent: it only appends if the line is absent, so re-running the installer does not produce duplicates.

### It Falls Back to Cron on Everything Else

RHEL, Fedora, Arch, openSUSE, and Alpine do not ship the `update-motd` framework. For these distros, the installer sets up a cron job instead:

```bash
(crontab -l 2>/dev/null | grep -v "generate-motd"; \
 echo "* * * * * /usr/local/bin/generate-motd > /etc/motd 2>/dev/null") | crontab -
```

This writes to `/etc/motd` every minute — the finest cron granularity. The MOTD will be at most 60 seconds stale, which is entirely acceptable for uptime and load data. The crontab manipulation follows the canonical safe pattern: read existing entries, strip any previous `generate-motd` lines to prevent duplicates on re-run, append the new entry, write back atomically.

`PrintMotd yes` is ensured in `sshd_config`, handling both commented-out and absent variants.

### Weather Caching: It Respects the Service

Because the generator runs on every login, an uncached implementation would issue a `curl` call per SSH session. On a busy server with ten admins logging in throughout the day, that adds up. More importantly, it is just rude to hammer a free public API.

The generator caches the weather response for 30 minutes:

```bash
CACHE_FILE="/var/cache/motd-weather"
CACHE_TTL=1800

NOW=$(date +%s)
if [[ -f "${CACHE_FILE}" ]]; then
    CACHE_AGE=$(( NOW - $(stat -c %Y "${CACHE_FILE}") ))
    [[ ${CACHE_AGE} -lt ${CACHE_TTL} ]] && WEATHER=$(cat "${CACHE_FILE}")
fi

if [[ -z "${WEATHER:-}" ]]; then
    WEATHER=$(curl -s --connect-timeout 4 --max-time 6 "${WEATHER_URL}" 2>/dev/null)
    [[ -n "${WEATHER}" ]] && echo "${WEATHER}" > "${CACHE_FILE}"
fi
```

`stat -c %Y` returns the file's last modification time as a Unix timestamp. Subtract from `$(date +%s)` and you have cache age in seconds — pure shell arithmetic, no `bc` or `awk` required. The cache file is only written on a non-empty response, which prevents an empty string from being cached as valid data during a network outage.

### SSH Reload Without Dropping Sessions

After install, the SSH daemon is reloaded with `systemctl reload` rather than `restart`. This sends SIGHUP to sshd, which causes it to re-read its configuration without terminating existing sessions — essential on production boxes where your current connection may be the only way in. The script handles both `sshd` (RHEL naming) and `ssh` (Debian naming).

---

## The Finished Result

After running `sudo bash install-motd.sh`, answering the location prompt, and watching the installer complete, you get an immediate preview of your new MOTD right in the terminal. No reboot required. No SSH reconnect needed to verify it worked.

The next login — from anywhere — greets you with a hostname banner in cyan, load and uptime at a glance, a memory breakdown that actually means something, and the current weather at your location. The whole thing renders in well under a second on any modern machine.

---

## Get It

The project is on GitHub:

**[https://github.com/ciberjohn/lealdasilva/tree/main/motd-improver](https://github.com/ciberjohn/lealdasilva/tree/main/motd-improver)**

One-liner install on any supported distro:

```bash
sudo bash install-motd.sh
```

Supported distributions: Ubuntu, Debian, Raspberry Pi OS, Linux Mint, Pop!_OS, RHEL, Rocky Linux, AlmaLinux, CentOS, Fedora, Arch Linux, Manjaro, openSUSE, and Alpine. If you are running something not on that list, open an issue — the detection logic is straightforward to extend.

---

## Where to Take It From Here

The generator at `/usr/local/bin/generate-motd` is plain Bash. It is easy to extend:

- **Disk usage** — add a `df -h` pass for your most important mount points
- **Docker status** — `docker ps --format` for a quick container count
- **Git branch** — if your servers have active repos, show the current branch and last commit
- **SSL certificate expiry** — a quiet warning when a cert is within 30 days of expiry is genuinely useful
- **Custom colour scheme** — the ANSI variables are all in one block at the top, easy to remap

The weather location is baked into the generator at install time as a literal URL, so changing it means re-running the installer with a new location — a thirty-second job.

If you find this useful, a star on the repo is appreciated. If you extend it in an interesting direction, consider opening a pull request. The project is deliberately kept simple — the goal is a script you can read and trust, not a framework.

---

*Tags: `Linux` `Bash` `DevOps` `SysAdmin` `Ubuntu`*
