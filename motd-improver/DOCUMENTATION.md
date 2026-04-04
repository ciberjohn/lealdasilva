# Custom Dynamic MOTD — Technical Documentation

> **Source:** [github.com/ciberjohn/lealdasilva/tree/main/motd-improver](https://github.com/ciberjohn/lealdasilva/tree/main/motd-improver)

## 1. Introduction

This project provides three Bash scripts that install and manage a custom dynamic Message of the Day (MOTD) on Linux systems. Rather than presenting users with the default, often cluttered MOTD output, these scripts deploy a clean, information-dense banner that appears at every SSH login (and interactive terminal session).

The banner displays:

- An ASCII art hostname rendered via `figlet`, with a Unicode box-drawing fallback
- Current date, time, system uptime, and load average
- Memory utilisation breakdown (used, free, cached, committed, swap)
- Live weather conditions from `wttr.in`

The three scripts represent an evolution from a simple Ubuntu-specific installer to a production-grade, multi-distribution tool. Each is a complete, standalone deployment unit — you do not need to run all three.

---

## 2. Overview of the Three Scripts

| Script | Scope | Privilege model | Distro support | Key additions |
|---|---|---|---|---|
| `setup-motd.sh` | Simple installer | Must run as root | Ubuntu only | figlet banner, basic stats |
| `update-motd.sh` | Re-deploy/update | Uses `sudo` internally | Ubuntu/Debian | Adds memory and weather stats |
| `install-motd.sh` | Production installer | Must run as root | Multi-distro | OS detection, package manager abstraction, weather prompt, caching, cron fallback, PAM repair |

**When to use which:**

- `setup-motd.sh` — Proof of concept or a quick one-time setup on a single Ubuntu machine where you are already root.
- `update-motd.sh` — Updating an existing deployment, or re-deploying from a non-root shell (it calls `sudo` as needed). Suited to Ubuntu/Debian where the `update-motd` framework is present.
- `install-motd.sh` — Any production deployment, any supported distribution. This is the script to reach for by default.

---

## 3. `setup-motd.sh` — Section-by-Section Breakdown

### 3.1 Shebang and Safety Flags

```bash
#!/bin/bash
set -euo pipefail
```

`set -euo pipefail` is a standard safety triplet:

- `-e` — Exit immediately if any command returns a non-zero status.
- `-u` — Treat references to unset variables as errors. Prevents silent failures from typos in variable names.
- `-o pipefail` — A pipeline's exit status is that of the rightmost command to fail, not the last command. Without this, `false | true` would return 0.

This script assumes it runs as root. There is no explicit root check — if it is invoked as a non-privileged user, the `apt-get` and `cp` calls to `/etc/update-motd.d/` will fail immediately due to permission errors, which is an acceptable implicit guard for a simple script.

### 3.2 Dependency Installation

```bash
apt-get install -y figlet
```

`figlet` generates the large ASCII art hostname banner. The `-y` flag suppresses the interactive confirmation prompt, making the script non-interactive. The script does not check whether `figlet` is already installed; `apt-get install -y` on an already-installed package is idempotent on Debian-based systems.

### 3.3 Backup Logic

```bash
TARGET="${MOTD_DIR}/00-header"
cp "${TARGET}" "${TARGET}.bak"
```

Before overwriting the system's default `00-header`, the original is preserved as `00-header.bak`. This is a single-level backup — running the script a second time will silently overwrite the `.bak` with whatever was already written by the first run. For a one-shot install this is sufficient; the production script (`install-motd.sh`) avoids this ambiguity entirely by writing to a new file (`00-custom`) and leaving the originals untouched.

### 3.4 The Embedded MOTD Script (Heredoc)

The `cat > "${TARGET}" << 'MOTD_SCRIPT'` heredoc writes a complete, self-contained Bash script to `/etc/update-motd.d/00-header`. The single-quoted delimiter (`'MOTD_SCRIPT'`) is critical: it instructs the shell to treat the heredoc body as a literal string, suppressing all variable expansion and command substitution. This is the correct behaviour — the variables inside (`${DATE}`, `${HOST}`, etc.) must be expanded at login time by the installed script, not at install time by `setup-motd.sh`.

#### Colour Variables

```bash
CY='\033[0;36m'   # cyan
GR='\033[0;32m'   # green
YL='\033[1;33m'   # yellow
WH='\033[1;37m'   # bold white
DM='\033[2;37m'   # dim white
NC='\033[0m'      # reset
```

These are ANSI escape sequences stored as shell variables. They are passed to `printf` (not `echo -e`) because `printf` handles escape sequences portably and predictably. `\033` is the octal escape for the ESC character (decimal 27). `NC` (no colour) resets all attributes to the terminal default — failing to reset after each coloured segment would cause colour to bleed into subsequent output.

#### Stats Gathering

```bash
DATE=$(date '+%A, %d %B %Y')
TIME=$(date '+%H:%M:%S %Z')
UPTIME=$(uptime -p | sed 's/^up //')
LOAD=$(awk '{print $1", "$2", "$3}' /proc/loadavg)
CPUS=$(nproc)
HOST=$(hostname -s)
FQDN=$(hostname -f)
```

All stat collection occurs at the top of the script, before any output. This avoids interleaved timing differences if the terminal is slow to render. Notable points:

- `uptime -p` outputs a human-readable string (e.g., `up 3 days, 2 hours`); the `sed` strips the leading `up ` prefix.
- `/proc/loadavg` contains five space-separated fields; `awk` extracts the 1-, 5-, and 15-minute load averages.
- `hostname -s` returns only the short hostname (no domain); `hostname -f` returns the FQDN. If DNS is not configured correctly, `hostname -f` may block briefly before returning an error — a known trade-off in this simple implementation.

#### figlet Banner with ASCII Fallback

```bash
if command -v figlet &>/dev/null; then
    printf "${CY}"
    figlet -f slant "${HOST}" 2>/dev/null || figlet "${HOST}"
    printf "${NC}"
else
    INNER="  ${HOST}  "
    LEN=${#INNER}
    TOP="╔$(printf '═%.0s' $(seq 1 $LEN))╗"
    MID="║${INNER}║"
    BOT="╚$(printf '═%.0s' $(seq 1 $LEN))╝"
    ...
fi
```

`command -v figlet` tests for the presence of `figlet` without spawning a subshell for `which`, which is not POSIX-reliable. The `&>/dev/null` redirect suppresses both stdout and stderr from the check itself.

`figlet -f slant` uses the `slant` font. If the font file is absent (some minimal `figlet` packages omit extra fonts), the `|| figlet "${HOST}"` fallback attempts the default font.

The fallback uses Unicode box-drawing characters (`╔`, `═`, `╗`, `║`, `╚`, `╝`) to construct a border around the hostname. `${#INNER}` is the Bash parameter expansion for string length. `printf '═%.0s'` with a sequence from `seq` is a portable idiom for repeating a character N times — `%.0s` formats any argument as a zero-width string, so the character `═` is printed once per argument regardless of argument value.

#### Divider and Stats Block

```bash
printf "${DM}  %s${NC}\n" "$(printf '─%.0s' {1..72})"
printf "  ${YL}%-16s${NC} ${WH}%s${NC}\n"  "Date"  "${DATE}"
```

The divider uses the same repeat-character idiom with `{1..72}` brace expansion. The stats block uses `printf` with `%-16s` (left-aligned, 16-character field width) to produce consistent two-column alignment regardless of label length. All colour variables are embedded directly in the format string rather than passed as arguments, which is intentional: format-string colour sequences do not consume a `%s` slot.

### 3.5 Disabling Noisy Default Scripts

```bash
chmod -x \
    "${MOTD_DIR}/50-landscape-sysinfo" \
    "${MOTD_DIR}/50-motd-news" \
    "${MOTD_DIR}/10-help-text" \
    2>/dev/null || true
```

Ubuntu ships several MOTD scripts that produce verbose or promotional output (`landscape-sysinfo`, `motd-news`, Ubuntu help text). Removing execute permission prevents `run-parts` from invoking them, without deleting the files. The `2>/dev/null || true` ensures the script does not abort if any of these files do not exist on a given system — a practical concession to `-e` mode.

### 3.6 Preview Step

```bash
run-parts --loglevel=0 "${MOTD_DIR}" 2>/dev/null || bash "${TARGET}"
```

`run-parts` executes all executable scripts in the MOTD directory in lexicographic order, reproducing exactly what the PAM MOTD module would display. If `run-parts` fails (not present or returns an error), the fallback directly executes the new header script. The `--loglevel=0` flag suppresses `run-parts` progress messages.

---

## 4. `update-motd.sh` — Section-by-Section Breakdown

### 4.1 Differences from `setup-motd.sh`

| Aspect | `setup-motd.sh` | `update-motd.sh` |
|---|---|---|
| Privilege model | Runs as root directly | Calls `sudo tee`, `sudo chmod`, etc. |
| `figlet` installation | Installs automatically | Assumes already installed |
| Backup | Takes `.bak` of original | No backup — pure re-deploy |
| Memory stats | Not present | Full `/proc/meminfo` breakdown |
| Weather | Not present | Live fetch from `wttr.in` |
| Static `/etc/motd` | Not handled | Explicitly truncated |
| Target file | Overwrites `00-header` | Overwrites `00-header` |

The `sudo tee` pattern is used because `sudo > file` redirection does not work as expected in Bash — the shell opens the file before `sudo` escalates privileges, so the redirect runs as the invoking user. `sudo tee FILE > /dev/null` routes the heredoc through `tee` which runs under sudo, correctly writing to a root-owned file.

### 4.2 Memory Stats from `/proc/meminfo`

```bash
read -r MEM_TOTAL MEM_FREE MEM_AVAIL BUFFERS CACHED SWAP_TOTAL SWAP_FREE COMMIT_AS COMMIT_LIMIT <<< \
    $(awk '/^MemTotal:/{mt=$2} /^MemFree:/{mf=$2} /^MemAvailable:/{ma=$2}
           /^Buffers:/{bu=$2} /^Cached:/{ca=$2}
           /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
           /^Committed_AS:/{cas=$2} /^CommitLimit:/{cl=$2}
           END{print mt,mf,ma,bu,ca,st,sf,cas,cl}' /proc/meminfo)
```

A single `awk` pass over `/proc/meminfo` extracts all required fields simultaneously, avoiding nine separate `grep`/`awk` invocations. The here-string (`<<<`) feeds the awk output directly into `read`, splitting it into named variables. All values are in kibibytes as reported by the kernel.

| Variable | Source field | Meaning |
|---|---|---|
| `MEM_TOTAL` | `MemTotal` | Total physical RAM installed |
| `MEM_FREE` | `MemFree` | RAM with no current use — genuinely idle |
| `MEM_AVAIL` | `MemAvailable` | RAM available to start new applications without swapping (accounts for reclaimable caches) |
| `BUFFERS` | `Buffers` | Memory used for kernel I/O buffers (block device metadata) |
| `CACHED` | `Cached` | Page cache — file data cached in RAM, reclaimable under pressure |
| `SWAP_TOTAL` | `SwapTotal` | Total swap space configured |
| `SWAP_FREE` | `SwapFree` | Swap currently unused |
| `COMMIT_AS` | `Committed_AS` | Total memory committed to all processes (including virtual allocations not yet backed by physical pages) |
| `COMMIT_LIMIT` | `CommitLimit` | Maximum memory the kernel will commit under the current overcommit policy |

```bash
MEM_USED_PCT=$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))
```

`MEM_USED_PCT` is calculated against `MEM_AVAIL` rather than `MEM_FREE`. This is the correct metric for operational awareness: `MEM_FREE` will appear very low on a healthy, active system because the kernel aggressively uses spare RAM for caching. `MEM_AVAIL` reflects what is actually available for new workloads.

```bash
COMMIT_PCT=$(( COMMIT_AS * 100 / COMMIT_LIMIT ))
```

The commit percentage reveals memory pressure at the virtual address space level. A value consistently above 80–90% indicates the system may have difficulty allocating new memory even if physical RAM appears available — a useful early warning for capacity planning.

```bash
[[ "${SWAP_TOTAL}" -gt 0 ]] && SWAP_PCT=$(( (SWAP_TOTAL - SWAP_FREE) * 100 / SWAP_TOTAL )) || SWAP_PCT=0
```

The conditional guard prevents division by zero on systems with no swap configured.

### 4.3 Weather via `wttr.in`

```bash
WEATHER=$(curl -s --connect-timeout 4 --max-time 6 "wttr.in/Mountain+Ash,Wales?format=3" 2>/dev/null)
```

`wttr.in` is a console-oriented weather service. The `?format=3` query parameter requests the compact single-line format: `Location: ⛅ +12°C`. Spaces in the location are replaced with `+`.

Timeout parameters are deliberately conservative:
- `--connect-timeout 4` — abandon TCP connection attempts after 4 seconds, avoiding a stall during DNS resolution failure or unreachable service.
- `--max-time 6` — hard cap on total request time, covering slow responses after connection.

If `curl` fails or returns an empty string, the weather line falls back to `(unavailable)` rather than suppressing the row entirely, which preserves consistent column alignment in the output.

**Note:** The location `Mountain+Ash,Wales` is hardcoded in `update-motd.sh`. The production `install-motd.sh` replaces this with an interactive prompt and bakes the user-supplied location in at install time.

### 4.4 Static `/etc/motd` Truncation

```bash
if [ -s /etc/motd ]; then
    sudo truncate -s 0 /etc/motd
fi
```

On Debian/Ubuntu systems, PAM's `pam_motd.so` module displays two sources: the dynamic scripts in `/etc/update-motd.d/` and the static file `/etc/motd`. If `/etc/motd` contains content (non-zero size, hence `-s`), it will be printed in addition to the dynamic output, producing duplication. `truncate -s 0` zeroes the file without deleting it — the file must exist for some PAM configurations to function correctly.

---

## 5. `install-motd.sh` — Section-by-Section Breakdown

### 5.1 Colour and Logging Helpers

```bash
info() { printf "\e[0;36m[INFO]\e[0m  %s\n" "$*"; }
ok()   { printf "\e[0;32m[ OK ]\e[0m  %s\n" "$*"; }
warn() { printf "\e[1;33m[WARN]\e[0m  %s\n" "$*"; }
die()  { printf "\e[0;31m[FAIL]\e[0m  %s\n" "$*" >&2; exit 1; }
```

Four logging functions provide consistent, colour-coded terminal output throughout the installer. `die()` writes to stderr (`>&2`) and terminates with exit code 1 — the convention for fatal error conditions. Using functions rather than inline `printf` calls makes the output style consistent and easy to change globally.

### 5.2 Root Check

```bash
[[ $EUID -ne 0 ]] && die "Run as root (sudo $0)"
```

`$EUID` (effective user ID) is a Bash built-in that does not require a subprocess, unlike `$(id -u)`. The check is at the very top of the script, before any OS detection or package manager operations, so the failure message is immediate and unambiguous.

### 5.3 OS Detection

```bash
source /etc/os-release
OS_FAMILY=""
case "${ID}" in
    ubuntu|debian|raspbian|linuxmint|pop|elementary|kali|parrot) OS_FAMILY="debian" ;;
    rhel|centos|rocky|almalinux|ol|scientific)                    OS_FAMILY="rhel"   ;;
    fedora)                                                        OS_FAMILY="fedora" ;;
    arch|manjaro|endeavouros|garuda)                               OS_FAMILY="arch"   ;;
    opensuse*|sles)                                                OS_FAMILY="suse"   ;;
    alpine)                                                        OS_FAMILY="alpine" ;;
esac

if [[ -z "${OS_FAMILY}" && -n "${ID_LIKE:-}" ]]; then
    case "${ID_LIKE}" in
        *debian*) OS_FAMILY="debian" ;;
        *rhel*|*fedora*|*centos*) OS_FAMILY="rhel" ;;
        ...
    esac
fi
```

`/etc/os-release` is the standard machine-readable OS identification file on systemd-based Linux distributions (and Alpine). `source`-ing it imports `ID`, `ID_LIKE`, `VERSION_ID`, `PRETTY_NAME`, and related variables into the current shell.

The `ID_LIKE` fallback is important: derivative distributions (e.g., Linux Mint derives from Ubuntu, which derives from Debian) may set `ID=linuxmint` but also `ID_LIKE="ubuntu debian"`. If the primary `ID` match fails — because the script's case statement does not enumerate every possible derivative — the `ID_LIKE` field provides a secondary classification against the upstream family. This makes the detection logic forward-compatible with new derivatives without code changes.

If neither match succeeds, `die` is called with a message listing the unsupported OS, and the installer aborts cleanly.

### 5.4 Package Manager Detection

```bash
if   command -v apt-get  &>/dev/null; then PKG_MGR="apt"
elif command -v dnf      &>/dev/null; then PKG_MGR="dnf"
elif command -v yum      &>/dev/null; then PKG_MGR="yum"
elif command -v pacman   &>/dev/null; then PKG_MGR="pacman"
elif command -v zypper   &>/dev/null; then PKG_MGR="zypper"
elif command -v apk      &>/dev/null; then PKG_MGR="apk"
else die "No supported package manager found."
fi
```

Package manager detection is performed separately from OS family detection deliberately. This decoupling means the installer can function correctly on non-standard distributions where the OS family might be known but the package manager has been changed — for example, an RHEL system where `dnf` is installed but `yum` is a symlink, or a Debian derivative that ships `apt-get` but not `apt`. Detection is by binary presence, which is the most reliable runtime test.

### 5.5 `install_pkg()` Function

```bash
install_pkg() {
    local pkg="$1"
    case "${PKG_MGR}" in
        apt)    apt-get install -y "${pkg}" ;;
        dnf)    dnf install -y "${pkg}"     ;;
        yum)    yum install -y "${pkg}"     ;;
        pacman) pacman -Sy --noconfirm "${pkg}" ;;
        zypper) zypper install -y "${pkg}"  ;;
        apk)    apk add --no-cache "${pkg}" ;;
    esac
}
```

A thin abstraction that maps a single package name to the correct package manager invocation. All package managers are called with their respective non-interactive flags (`-y`, `--noconfirm`, `--no-cache`). This function is the only place package manager syntax needs to be maintained.

**Limitation:** Package names are not always consistent across distributions. `figlet` is `figlet` on most systems but may differ on some. The function handles syntax differences; name differences would require a lookup table (not implemented, as `figlet` and `curl` are universally named across the supported distributions).

### 5.6 Dependency Check Loop

```bash
for dep in curl figlet; do
    if ! command -v "${dep}" &>/dev/null; then
        info "Installing ${dep}..."
        install_pkg "${dep}"
    else
        ok "${dep} already installed"
    fi
done
```

Iterating over dependencies and checking each individually avoids installing packages that are already present (reducing unnecessary network traffic and package manager overhead). `command -v` is used rather than `which` for POSIX correctness.

### 5.7 Weather Location Prompt and `urlencode()`

```bash
read -rp "Enter weather location (e.g. London,UK): " WEATHER_LOC
```

The `-r` flag to `read` disables backslash interpretation, ensuring that locations containing backslashes (unusual but possible) are accepted literally.

```bash
urlencode() {
    local string="${1}"
    local encoded=""
    local i c o
    for (( i=0; i<${#string}; i++ )); do
        c="${string:i:1}"
        case "${c}" in
            [a-zA-Z0-9.~_-]) o="${c}" ;;
            ' ')              o="+"   ;;
            *)                printf -v o '%%%02X' "'${c}" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}
```

`urlencode()` is a pure-Bash URL encoder — it does not depend on `python3`, `perl`, or `jq`. The logic iterates character by character using Bash substring extraction (`${string:i:1}`). Characters in the unreserved set (`a-z`, `A-Z`, `0-9`, `.`, `~`, `_`, `-`) are passed through unchanged. Spaces become `+` (appropriate for query string parameters). All other characters are percent-encoded using `printf -v o '%%%02X' "'${c}"` — the `'${c}` (single quote followed by character) is a `printf` construct that converts a character to its ASCII decimal value, which `%02X` then formats as two uppercase hex digits.

### 5.8 `wttr.in` Validation

```bash
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

Validation performs a live request to `wttr.in` at install time. Three outcomes are handled:
1. Empty response — network is unreachable. The installer continues with a warning rather than aborting, since weather is a non-critical feature.
2. Known error strings in the response — `wttr.in` returns human-readable error text (not an HTTP error code) for unrecognised locations. A grep for known error phrases catches this.
3. Successful response — the weather line is printed as confirmation of the validated location.

This check also verifies that `curl` and DNS resolution are working correctly before the generator script is installed.

### 5.9 Generator Script Creation

The installer writes `/usr/local/bin/generate-motd` using a heredoc with **mixed quoting** — the outer delimiter is unquoted (`EOF`), but variables intended to be frozen at install time are captured in the surrounding shell context, whilst variables that must expand at runtime are escaped.

```bash
cat > /usr/local/bin/generate-motd << EOF
#!/bin/bash
# Location baked in at install time:
WEATHER_URL="wttr.in/${ENCODED_LOC}?format=3"

DATE=\$(date '+%A, %d %B %Y')
HOST=\$(hostname -s)
...
EOF
```

- `${ENCODED_LOC}` — **unescaped** — expands to the validated location string at install time and is literally embedded in the generated script.
- `\$(date ...)`, `\$(hostname -s)` — **escaped** — the backslash-dollar prevents expansion now; the resulting script contains a literal `$(date ...)` that expands at runtime on each login.

This is the fundamental distinction: install-time expansion bakes in configuration; runtime expansion produces live data. Getting this wrong in either direction produces either a broken script (empty variables) or stale data (timestamp frozen at install time).

### 5.10 Weather Caching Logic

```bash
CACHE_FILE="/var/cache/motd-weather"
CACHE_TTL=1800   # 30 minutes

NOW=$(date +%s)
if [[ -f "${CACHE_FILE}" ]]; then
    CACHE_AGE=$(( NOW - $(stat -c %Y "${CACHE_FILE}") ))
    if [[ ${CACHE_AGE} -lt ${CACHE_TTL} ]]; then
        WEATHER=$(cat "${CACHE_FILE}")
    fi
fi

if [[ -z "${WEATHER:-}" ]]; then
    WEATHER=$(curl -s --connect-timeout 4 --max-time 6 "${WEATHER_URL}" 2>/dev/null)
    [[ -n "${WEATHER}" ]] && echo "${WEATHER}" > "${CACHE_FILE}"
fi
```

Weather data is fetched at most once every 30 minutes. This is important because `/etc/update-motd.d/` scripts execute on every login — on a busy server with multiple concurrent SSH sessions, an uncached implementation would issue a `curl` call per login, potentially flooding `wttr.in` and introducing login latency.

`stat -c %Y` retrieves the file's last modification time as a Unix timestamp (seconds since epoch). Subtracting from `$(date +%s)` gives cache age in seconds. The comparison uses integer arithmetic built into the shell — no `bc` or `awk` dependency.

The cache file is written only when `curl` returns a non-empty response, preventing an empty file from being cached as valid data.

### 5.11 `setup_debian()`

For Debian/Ubuntu systems, the script integrates with the existing `update-motd` framework:

```bash
setup_debian() {
    # Disable noisy default scripts
    for f in /etc/update-motd.d/10-help-text \
              /etc/update-motd.d/50-landscape-sysinfo \
              /etc/update-motd.d/50-motd-news \
              /etc/update-motd.d/80-livepatch \
              /etc/update-motd.d/95-hwe-eol; do
        [[ -f "${f}" ]] && chmod -x "${f}" && info "Disabled: ${f}"
    done

    # Write thin wrapper
    cat > /etc/update-motd.d/00-custom << 'WRAPPER'
#!/bin/bash
/usr/local/bin/generate-motd
WRAPPER
    chmod 755 /etc/update-motd.d/00-custom

    # Fix PAM config
    ...
}
```

The wrapper script in `/etc/update-motd.d/` is intentionally minimal — it simply calls `generate-motd`. Separating concerns means the generator can be updated, tested, or called independently without touching the PAM integration layer.

**PAM `pam_motd.so` Repair:**

On some Ubuntu releases, PAM's MOTD configuration has been altered by system updates or third-party packages to disable dynamic MOTD execution. The script repairs this by ensuring `/etc/pam.d/sshd` and `/etc/pam.d/login` contain the correct `pam_motd.so` lines:

```bash
if ! grep -q "pam_motd.so.*motd=/run/motd.dynamic" /etc/pam.d/sshd 2>/dev/null; then
    echo "session optional pam_motd.so motd=/run/motd.dynamic noupdate" >> /etc/pam.d/sshd
    warn "Added pam_motd.so line to /etc/pam.d/sshd"
fi
```

The `motd=/run/motd.dynamic` parameter points PAM at the dynamically-generated MOTD file rather than the static `/etc/motd`. The `noupdate` flag tells PAM not to attempt regenerating the dynamic MOTD itself (the `update-motd` framework handles this separately). This repair is only applied if the line is absent — it does not duplicate entries.

### 5.12 `setup_cron()`

On non-Debian systems that lack the `update-motd` framework, a cron job is used instead:

```bash
setup_cron() {
    # Install cron job
    (crontab -l 2>/dev/null | grep -v "generate-motd"; \
     echo "* * * * * /usr/local/bin/generate-motd > /etc/motd 2>/dev/null") | crontab -

    # Ensure SSH shows MOTD
    sed -i 's/^#\?PrintMotd.*/PrintMotd yes/' /etc/ssh/sshd_config
    grep -q "^PrintMotd" /etc/ssh/sshd_config || echo "PrintMotd yes" >> /etc/ssh/sshd_config

    # Trigger immediate generation
    /usr/local/bin/generate-motd > /etc/motd
}
```

The cron pattern `* * * * *` runs every minute — the finest granularity available via cron. This means the MOTD file is at most 60 seconds stale, which is acceptable for the data presented.

The crontab manipulation uses the canonical safe pattern: read the existing crontab, strip any previous `generate-motd` entries (preventing duplicates on re-run), append the new line, and write back in a single atomic operation. The `2>/dev/null` on `crontab -l` suppresses the "no crontab for root" error on a fresh system.

`PrintMotd yes` in `sshd_config` instructs OpenSSH to display `/etc/motd` after authentication. The `sed` command handles both commented-out (`#PrintMotd no`) and active (`PrintMotd no`) variants. The `grep || echo` fallback appends the directive if no `PrintMotd` line exists at all.

**PAM fallback for non-Debian systems:**

Some RHEL/Fedora systems use PAM with `pam_motd.so` for MOTD display. The `setup_cron()` function additionally checks whether `pam_motd.so` is referenced in `/etc/pam.d/sshd` and adds it if not, mirroring the Debian PAM repair logic.

### 5.13 OS Family Routing

```bash
case "${OS_FAMILY}" in
    debian) setup_debian ;;
    rhel|fedora|arch|suse|alpine) setup_cron ;;
    *) die "Unhandled OS family: ${OS_FAMILY}" ;;
esac
```

The routing is binary: Debian/Ubuntu get the `update-motd` framework integration; everything else gets the cron-based approach. This is deliberate — attempting to replicate Ubuntu's `update-motd` framework on RHEL would introduce significant complexity for marginal benefit. The cron approach is universally compatible.

### 5.14 SSH Daemon Reload

```bash
if command -v systemctl &>/dev/null && systemctl is-active sshd &>/dev/null; then
    systemctl reload sshd && ok "SSH daemon reloaded"
elif command -v systemctl &>/dev/null && systemctl is-active ssh &>/dev/null; then
    systemctl reload ssh && ok "SSH daemon reloaded"
fi
```

`reload` (SIGHUP) rather than `restart` is used to apply `sshd_config` changes. This causes sshd to re-read its configuration without terminating existing sessions — a critical distinction on production systems where an active session is the only means of access. The dual-name check (`sshd` vs `ssh`) handles the naming difference between RHEL-family systems (service name `sshd`) and Debian-family systems (service name `ssh`).

### 5.15 Post-Install Preview

```bash
info "Previewing MOTD..."
if [[ "${OS_FAMILY}" == "debian" ]]; then
    run-parts /etc/update-motd.d/
else
    /usr/local/bin/generate-motd
fi
```

Executing the MOTD immediately after install provides instant visual confirmation that the deployment succeeded. For Debian/Ubuntu, `run-parts` is used to simulate the full PAM-triggered execution chain. For other distros, the generator is called directly.

---

## 6. Prerequisites and Compatibility Matrix

### Prerequisites

| Requirement | Detail |
|---|---|
| Root access | Required for all three scripts |
| Bash 4.0+ | Required for associative arrays and `[[ ]]` constructs used in `install-motd.sh` |
| `curl` | Required for weather fetching (installed automatically by `install-motd.sh`) |
| `figlet` | Required for ASCII banner (installed automatically by all scripts) |
| Internet access | Required for weather data (gracefully degraded if absent) |
| `wttr.in` reachable | Optional; MOTD functions without weather if unavailable |

### Compatibility Matrix

| Distribution | `setup-motd.sh` | `update-motd.sh` | `install-motd.sh` | Method used |
|---|---|---|---|---|
| Ubuntu 20.04 / 22.04 / 24.04 | Yes | Yes | Yes | `update-motd.d` + PAM |
| Debian 11 / 12 | Partial* | Partial* | Yes | `update-motd.d` + PAM |
| Linux Mint | No | No | Yes | `update-motd.d` + PAM |
| Raspberry Pi OS | No | No | Yes | `update-motd.d` + PAM |
| RHEL 8 / 9 | No | No | Yes | cron + `/etc/motd` |
| Rocky Linux 8 / 9 | No | No | Yes | cron + `/etc/motd` |
| AlmaLinux 8 / 9 | No | No | Yes | cron + `/etc/motd` |
| CentOS Stream 9 | No | No | Yes | cron + `/etc/motd` |
| Fedora 38+ | No | No | Yes | cron + `/etc/motd` |
| Arch Linux | No | No | Yes | cron + `/etc/motd` |
| openSUSE Leap / Tumbleweed | No | No | Yes | cron + `/etc/motd` |
| Alpine Linux | No | No | Yes | cron + `/etc/motd` |

*`setup-motd.sh` and `update-motd.sh` will function on Debian but assume Ubuntu-specific default MOTD script names. The `chmod -x` calls on Ubuntu-specific files (`landscape-sysinfo`, `motd-news`) will silently pass on Debian systems due to `2>/dev/null || true`.

---

## 7. Usage Instructions

### Running `setup-motd.sh`

```bash
sudo bash setup-motd.sh
```

Must be executed as root. Requires an active internet connection to install `figlet` via `apt-get`. Designed for a first-time, one-off install on Ubuntu.

### Running `update-motd.sh`

```bash
bash update-motd.sh
```

Can be run as a normal user with `sudo` privileges. Re-deploys the MOTD header and adds memory/weather stats. Run this to update an existing installation or to switch to the enhanced version after initial setup with `setup-motd.sh`.

### Running `install-motd.sh`

```bash
sudo bash install-motd.sh
```

Must be executed as root. Interactive — prompts for a weather location. Internet access is used to validate the location against `wttr.in` at install time. On first run, the script will:

1. Detect the OS and package manager
2. Install `curl` and `figlet` if missing
3. Prompt for a weather location
4. Validate the location
5. Write `/usr/local/bin/generate-motd`
6. Configure MOTD delivery (PAM or cron, depending on OS)
7. Reload SSH
8. Display a live preview

Re-running `install-motd.sh` is safe — it is idempotent. The crontab deduplication logic and `grep || append` PAM configuration ensure multiple runs do not produce duplicate entries.

### Testing the MOTD Without Logging Out

**Debian/Ubuntu:**
```bash
sudo run-parts /etc/update-motd.d/
```

**All distros (direct generator call):**
```bash
sudo /usr/local/bin/generate-motd
```

**Simulate a login session:**
```bash
ssh localhost
```

---

## 8. Security Considerations

### Root Requirement

All three scripts write to `/etc/update-motd.d/`, `/usr/local/bin/`, and `/etc/pam.d/` — all root-owned directories. This is unavoidable for system-wide MOTD configuration. The scripts do not implement privilege escalation internally (beyond `sudo` calls in `update-motd.sh`) — they expect to be invoked with appropriate privilege.

### External `curl` Call

The MOTD generator makes an outbound HTTPS request to `wttr.in` on every execution (subject to the 30-minute cache). Operational considerations:

- **Egress filtering:** Servers in restricted environments may block outbound HTTPS to arbitrary hosts. The weather fetch will time out silently (6-second maximum) and display `(unavailable)` — no functional impact on the MOTD.
- **Data transmitted:** The request includes the configured location string and standard HTTP headers (User-Agent, Host). No system-identifying data beyond the location is sent.
- **Service availability:** `wttr.in` is a third-party service with no SLA. The caching layer mitigates impact: a service outage will display stale weather data until the cache expires, then fall back to `(unavailable)`.
- **DNS dependency:** `wttr.in` resolution is required. On systems with split-horizon DNS or restricted resolver policies, this lookup may fail. The timeout handling ensures this does not stall the login process.

If weather data is not acceptable from a security posture perspective, remove the weather block from `/usr/local/bin/generate-motd` after installation.

### PAM Modification

`install-motd.sh` and `update-motd.sh` modify `/etc/pam.d/sshd`. Incorrect PAM configuration can prevent all SSH logins. Mitigations in place:

- Changes are append-only or use `sed` to modify existing lines — the scripts do not rewrite PAM files wholesale.
- The added `pam_motd.so` line uses `optional` control flag, meaning PAM will not fail authentication if the module errors or is missing.
- Changes are checked with `grep` before application to prevent duplicate lines.
- Always maintain an active, authenticated session during any PAM modification to enable rollback if needed.

### File Permissions

- `/usr/local/bin/generate-motd` is installed with mode `755` (world-executable). This is correct — the script contains no secrets. The weather location is embedded in plaintext, which is expected.
- `/etc/update-motd.d/00-custom` is installed with mode `755`. The `update-motd` framework requires execute permission to invoke scripts via `run-parts`.
- `/var/cache/motd-weather` is written by root and readable by root. The MOTD generator runs as root (invoked by PAM or cron as root), so this is appropriate.

---

## 9. Customisation Guide

### Changing the Weather Location

**In `update-motd.sh`:** Edit the hardcoded URL before running:

```bash
# Find this line and update the location:
WEATHER=$(curl -s --connect-timeout 4 --max-time 6 "wttr.in/Mountain+Ash,Wales?format=3" 2>/dev/null)
```

**In an existing `install-motd.sh` deployment:** Edit the generator directly:

```bash
sudo nano /usr/local/bin/generate-motd
```

Find the `WEATHER_URL=` line and update the location. Spaces must be encoded as `+`. The location string accepts city names, postcodes, airport codes (e.g., `LHR`), and coordinates (e.g., `51.5,-3.2`).

To invalidate the weather cache immediately after changing location:

```bash
sudo rm -f /var/cache/motd-weather
```

### Changing the Weather Format

`wttr.in` supports several format strings. Change `?format=3` in the `WEATHER_URL`:

| Format | Output example |
|---|---|
| `?format=1` | `⛅` (emoji only) |
| `?format=2` | `⛅ +12°C` |
| `?format=3` | `Mountain Ash, Wales: ⛅ +12°C` (default used here) |
| `?format=4` | Multi-line summary |
| `?format=%c+%t` | Custom format — `%c` = emoji, `%t` = temperature |

### Adding New Stats Fields

New fields are added to `/usr/local/bin/generate-motd` in the stats block. Follow the existing `printf` pattern:

```bash
# Example: add disk usage for root filesystem
DISK_USED=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " used)"}')
printf "  ${YL}%-16s${NC} ${WH}%s${NC}\n" "Disk (/)" "${DISK_USED}"
```

Insert this after the existing `printf` lines for the stats block, before the footer divider. The `%-16s` format ensures the label column remains aligned with existing rows.

### Adjusting the Cache TTL

In `/usr/local/bin/generate-motd`, change the `CACHE_TTL` value (in seconds):

```bash
CACHE_TTL=1800   # 30 minutes — change to desired interval
```

For a server where weather data accuracy matters more than reducing API calls, a value of `300` (5 minutes) is reasonable. For a low-traffic server, `3600` (1 hour) reduces external calls further.

### Disabling Colour Output

Replace all colour variable references in the `printf` format strings with empty strings, or set all colour variables to an empty string at the top of `/usr/local/bin/generate-motd`:

```bash
CY=''; GR=''; YL=''; WH=''; DM=''; NC=''
```

This is useful for terminals that do not support ANSI colour codes, or for piping MOTD output to log files.
