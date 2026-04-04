#!/usr/bin/env bash
# =============================================================================
# install-motd.sh — Universal dynamic MOTD installer
# Supports: Debian/Ubuntu, RHEL/CentOS/Rocky/AlmaLinux, Fedora, Arch, openSUSE
# Must be run as root: sudo bash install-motd.sh
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYN='\033[0;36m'
BLD='\033[1m'; NC='\033[0m'

info() { echo -e "${CYN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GRN}[ OK ]${NC}  $*"; }
warn() { echo -e "${YLW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo bash $0"

# ── OS detection ──────────────────────────────────────────────────────────────
info "Detecting OS..."
[[ -f /etc/os-release ]] || die "/etc/os-release not found — cannot detect OS."
# shellcheck source=/dev/null
source /etc/os-release
OS_ID="${ID:-unknown}"
OS_ID_LIKE="${ID_LIKE:-}"
OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
OS_FAMILY="generic"

case "${OS_ID}" in
    ubuntu|debian|raspbian|linuxmint|pop)           OS_FAMILY="debian"  ;;
    rhel|centos|rocky|almalinux|ol|cloudlinux)      OS_FAMILY="rhel"    ;;
    fedora)                                          OS_FAMILY="rhel"    ;;
    arch|manjaro|endeavouros|garuda)                 OS_FAMILY="arch"    ;;
    opensuse*|sles)                                  OS_FAMILY="suse"    ;;
    alpine)                                          OS_FAMILY="alpine"  ;;
    *)
        [[ "${OS_ID_LIKE}" =~ debian  ]] && OS_FAMILY="debian"
        [[ "${OS_ID_LIKE}" =~ rhel|fedora ]] && OS_FAMILY="rhel"
        [[ "${OS_ID_LIKE}" =~ arch    ]] && OS_FAMILY="arch"
        [[ "${OS_ID_LIKE}" =~ suse    ]] && OS_FAMILY="suse"
        ;;
esac

# Detect package manager independently (more reliable than OS family alone)
PKG_MGR="unknown"
command -v apt-get &>/dev/null && PKG_MGR="apt"
command -v dnf     &>/dev/null && PKG_MGR="dnf"
command -v yum     &>/dev/null && [[ "${PKG_MGR}" == "unknown" ]] && PKG_MGR="yum"
command -v pacman  &>/dev/null && PKG_MGR="pacman"
command -v zypper  &>/dev/null && PKG_MGR="zypper"
command -v apk     &>/dev/null && PKG_MGR="apk"

ok "OS: ${OS_NAME} | Family: ${OS_FAMILY} | Package manager: ${PKG_MGR}"

# ── Dependency installer ───────────────────────────────────────────────────────
install_pkg() {
    local pkg="$1"
    case "${PKG_MGR}" in
        apt)    apt-get install -y -q "${pkg}" 2>/dev/null ;;
        dnf)    dnf install -y -q "${pkg}" 2>/dev/null     ;;
        yum)    yum install -y -q "${pkg}" 2>/dev/null     ;;
        pacman) pacman -Sy --noconfirm "${pkg}" 2>/dev/null ;;
        zypper) zypper -q install -y "${pkg}" 2>/dev/null  ;;
        apk)    apk add -q "${pkg}" 2>/dev/null             ;;
        *)      warn "Unknown package manager — install ${pkg} manually."; return 1 ;;
    esac
}

# ── Install dependencies ───────────────────────────────────────────────────────
echo ""
info "Checking dependencies..."
for dep in curl figlet; do
    if ! command -v "${dep}" &>/dev/null; then
        info "Installing ${dep}..."
        install_pkg "${dep}" && ok "${dep} installed." \
            || warn "${dep} could not be installed — some features may be degraded."
    else
        ok "${dep} already present."
    fi
done

# ── Weather location ──────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}Weather location${NC}"
echo "Enter a city/location. Examples:  London,UK   Mountain+Ash,Wales   Tokyo,Japan"
echo ""

urlencode() {
    local raw="$1" out="" i char
    for (( i=0; i<${#raw}; i++ )); do
        char="${raw:$i:1}"
        case "${char}" in
            [a-zA-Z0-9.~_+,-]) out+="${char}" ;;
            ' ') out+="+"       ;;
            *)   printf -v hex '%%%02X' "'${char}"; out+="${hex}" ;;
        esac
    done
    echo "${out}"
}

while true; do
    read -rp "Location: " RAW_LOCATION
    [[ -z "${RAW_LOCATION}" ]] && { warn "Location cannot be empty."; continue; }

    WEATHER_LOCATION="$(urlencode "${RAW_LOCATION}")"

    info "Validating with wttr.in..."
    WEATHER_TEST="$(curl -s --connect-timeout 6 --max-time 10 \
        "wttr.in/${WEATHER_LOCATION}?format=3" 2>/dev/null || true)"

    if [[ -n "${WEATHER_TEST}" ]] \
        && [[ "${WEATHER_TEST}" != *"Unknown location"* ]] \
        && [[ "${WEATHER_TEST}" != *"ERROR"* ]]; then
        ok "Confirmed: ${WEATHER_TEST}"
        break
    else
        warn "Could not resolve '${RAW_LOCATION}'. Check spelling and retry."
    fi
done

# ── Write the MOTD generator ───────────────────────────────────────────────────
GENERATOR="/usr/local/bin/generate-motd"
WEATHER_CACHE="/var/cache/motd-weather"

info "Writing generator: ${GENERATOR}"

# NOTE: heredoc is unquoted so ${WEATHER_LOCATION} and ${WEATHER_CACHE} expand
# now (install time). All runtime variables are escaped with \$.
cat > "${GENERATOR}" << GENEOF
#!/bin/bash
# generate-motd — Dynamic MOTD generator
# Location: ${GENERATOR}  |  Installed by install-motd.sh

CY='\033[0;36m'; GR='\033[0;32m'; YL='\033[1;33m'
WH='\033[1;37m'; DM='\033[2;37m'; NC='\033[0m'

DATE=\$(date '+%A, %d %B %Y')
TIME=\$(date '+%H:%M:%S %Z')
UPTIME=\$(uptime -p 2>/dev/null | sed 's/^up //' || uptime | awk -F'up ' '{print \$2}' | awk -F',' '{print \$1}')
LOAD=\$(awk '{print \$1", "\$2", "\$3}' /proc/loadavg)
CPUS=\$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)
HOST=\$(hostname -s 2>/dev/null || hostname)
FQDN=\$(hostname -f 2>/dev/null || hostname)

echo ""

if command -v figlet &>/dev/null; then
    printf "\${CY}"
    figlet -f slant "\${HOST}" 2>/dev/null || figlet "\${HOST}"
    printf "\${NC}"
else
    printf "\${CY}  ===  \${HOST}  ===\${NC}\n\n"
fi

printf "\${DM}  %s\${NC}\n" "\$(printf '─%.0s' {1..72})"
printf "  \${YL}%-16s\${NC} \${WH}%s\${NC}\n"  "Date"         "\${DATE}"
printf "  \${YL}%-16s\${NC} \${WH}%s\${NC}\n"  "Time"         "\${TIME}"
printf "  \${YL}%-16s\${NC} \${WH}%s\${NC}\n"  "Uptime"       "\${UPTIME}"
printf "  \${YL}%-16s\${NC} \${WH}%s\${NC}  \${DM}(%s CPU cores)\${NC}\n" \
    "Load average" "\${LOAD}" "\${CPUS}"
printf "  \${YL}%-16s\${NC} \${GR}%s\${NC}\n"  "Hostname"     "\${FQDN}"

# Memory
read -r MEM_TOTAL MEM_FREE MEM_AVAIL BUFFERS CACHED SWAP_TOTAL SWAP_FREE COMMIT_AS COMMIT_LIMIT <<< \
    \$(awk '/^MemTotal:/{mt=\$2} /^MemFree:/{mf=\$2} /^MemAvailable:/{ma=\$2}
           /^Buffers:/{bu=\$2} /^Cached:/{ca=\$2}
           /^SwapTotal:/{st=\$2} /^SwapFree:/{sf=\$2}
           /^Committed_AS:/{cas=\$2} /^CommitLimit:/{cl=\$2}
           END{print mt,mf,ma,bu,ca,st,sf,cas,cl}' /proc/meminfo)

MEM_USED_PCT=\$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))
MEM_FREE_PCT=\$(( MEM_FREE * 100 / MEM_TOTAL ))
MEM_CACHED_PCT=\$(( (CACHED + BUFFERS) * 100 / MEM_TOTAL ))
COMMIT_PCT=\$(( COMMIT_AS * 100 / COMMIT_LIMIT ))
[[ "\${SWAP_TOTAL}" -gt 0 ]] \
    && SWAP_PCT=\$(( (SWAP_TOTAL - SWAP_FREE) * 100 / SWAP_TOTAL )) \
    || SWAP_PCT=0

printf "  \${YL}%-16s\${NC} Used: \${WH}%s%%\${NC}  Free: \${WH}%s%%\${NC}  Cached: \${WH}%s%%\${NC}  Committed: \${WH}%s%%\${NC}  Swap: \${WH}%s%%\${NC}\n" \
    "Memory" "\${MEM_USED_PCT}" "\${MEM_FREE_PCT}" "\${MEM_CACHED_PCT}" "\${COMMIT_PCT}" "\${SWAP_PCT}"

# Weather — cached 30 minutes to avoid hammering wttr.in on every login
CACHE_FILE="${WEATHER_CACHE}"
CACHE_TTL=1800
NOW=\$(date +%s)
CACHE_AGE=\$(( NOW - \$(stat -c %Y "\${CACHE_FILE}" 2>/dev/null || echo 0) ))

if [[ ! -f "\${CACHE_FILE}" ]] || [[ \${CACHE_AGE} -gt \${CACHE_TTL} ]]; then
    WEATHER=\$(curl -s --connect-timeout 4 --max-time 6 \
        "wttr.in/${WEATHER_LOCATION}?format=3" 2>/dev/null || true)
    [[ -n "\${WEATHER}" ]] && echo "\${WEATHER}" > "\${CACHE_FILE}"
else
    WEATHER=\$(cat "\${CACHE_FILE}" 2>/dev/null || true)
fi

if [[ -n "\${WEATHER}" ]]; then
    printf "  \${YL}%-16s\${NC} \${WH}%s\${NC}\n" "Weather" "\${WEATHER}"
else
    printf "  \${YL}%-16s\${NC} \${DM}%s\${NC}\n" "Weather" "(unavailable)"
fi

printf "\${DM}  %s\${NC}\n\n" "\$(printf '─%.0s' {1..72})"
GENEOF

chmod 755 "${GENERATOR}"
ok "Generator written."

# ── OS-specific setup ─────────────────────────────────────────────────────────
echo ""
info "Configuring MOTD delivery for: ${OS_FAMILY}"

setup_debian() {
    local motd_dir="/etc/update-motd.d"
    local pam_sshd="/etc/pam.d/sshd"

    # Disable noisy default scripts
    for f in "${motd_dir}"/10-help-text \
              "${motd_dir}"/50-motd-news \
              "${motd_dir}"/50-landscape-sysinfo \
              "${motd_dir}"/51-cloudguest \
              "${motd_dir}"/91-contract-ua-esm-status; do
        [[ -f "${f}" ]] && chmod -x "${f}" && info "Disabled: $(basename "${f}")"
    done

    # Disable any existing 00-header (self-contained or ours)
    [[ -f "${motd_dir}/00-header" ]] \
        && chmod -x "${motd_dir}/00-header" \
        && info "Disabled: 00-header (replaced by 00-custom)"

    # Write thin wrapper that calls the generator
    cat > "${motd_dir}/00-custom" << 'WRAPEOF'
#!/bin/bash
exec /usr/local/bin/generate-motd
WRAPEOF
    chmod 755 "${motd_dir}/00-custom"
    ok "Created: ${motd_dir}/00-custom"

    # Ensure PAM uses /run/motd.dynamic (the correct Debian/Ubuntu config)
    if [[ -f "${pam_sshd}" ]]; then
        # Fix bare pam_motd.so line → pam_motd.so motd=/run/motd.dynamic
        if grep -qE 'pam_motd\.so\s*$' "${pam_sshd}"; then
            sed -i -E \
                's|^(session\s+optional\s+pam_motd\.so)\s*$|\1  motd=/run/motd.dynamic|' \
                "${pam_sshd}"
            ok "PAM: updated pam_motd.so to use motd=/run/motd.dynamic"
        elif grep -q 'motd=/run/motd.dynamic' "${pam_sshd}"; then
            ok "PAM: already correctly configured."
        fi
    fi

    # Silence the static /etc/motd
    truncate -s 0 /etc/motd

    # Generate immediately into /run/motd.dynamic
    "${GENERATOR}" > /run/motd.dynamic
    ok "Generated /run/motd.dynamic"
}

setup_cron() {
    # Generic approach: cron regenerates /etc/motd every minute;
    # SSH PrintMotd yes displays it.
    local cron_file="/etc/cron.d/motd-refresh"
    local sshd_config="/etc/ssh/sshd_config"
    local pam_sshd="/etc/pam.d/sshd"

    # Cron job — weather is cached in the generator so every-minute is cheap
    cat > "${cron_file}" << CRONEOF
# Refresh MOTD every minute (weather is cached 30 min inside the generator)
* * * * * root /usr/local/bin/generate-motd > /etc/motd 2>/dev/null
CRONEOF
    chmod 644 "${cron_file}"
    ok "Cron job installed: ${cron_file}"

    # Ensure cron daemon is running
    local cron_started=false
    for svc in crond cron anacron; do
        if systemctl list-units --type=service 2>/dev/null | grep -q "${svc}"; then
            systemctl enable --now "${svc}" 2>/dev/null && cron_started=true && break
        fi
    done
    "${cron_started}" || warn "Could not start cron — install cronie/cron manually."

    # SSH: PrintMotd yes so sshd displays /etc/motd on login
    if grep -q '^PrintMotd' "${sshd_config}" 2>/dev/null; then
        sed -i 's/^PrintMotd.*/PrintMotd yes/' "${sshd_config}"
    else
        echo "PrintMotd yes" >> "${sshd_config}"
    fi
    ok "SSH PrintMotd set to yes."

    # PAM motd display (shows /etc/motd on login, belt-and-braces)
    if [[ -f "${pam_sshd}" ]] && ! grep -q 'pam_motd' "${pam_sshd}"; then
        echo "session    optional     pam_motd.so noupdate" >> "${pam_sshd}"
        info "Added pam_motd.so to ${pam_sshd}"
    fi

    # Generate immediately
    "${GENERATOR}" > /etc/motd
    ok "Generated /etc/motd"
}

case "${OS_FAMILY}" in
    debian)                     setup_debian ;;
    rhel|arch|suse|alpine|generic) setup_cron   ;;
esac

# ── Reload SSH ────────────────────────────────────────────────────────────────
echo ""
info "Reloading SSH daemon..."
if   systemctl reload sshd 2>/dev/null; then ok "sshd reloaded."
elif systemctl reload ssh  2>/dev/null; then ok "ssh reloaded."
else warn "Could not reload SSH — restart it manually: systemctl restart sshd"
fi

# ── Preview ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}$(printf '━%.0s' {1..72})${NC}"
echo -e "${BLD} Installation complete — MOTD preview:${NC}"
echo -e "${GRN}$(printf '━%.0s' {1..72})${NC}"
echo ""
"${GENERATOR}"
echo -e "${GRN}$(printf '━%.0s' {1..72})${NC}"
echo ""
info "Generator: ${GENERATOR}"
info "Weather location: ${WEATHER_LOCATION} (cache: ${WEATHER_CACHE})"
info "To change location later, edit the wttr.in URL in ${GENERATOR}"
echo ""
