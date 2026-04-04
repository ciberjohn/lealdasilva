#!/bin/bash
#
#  setup-motd.sh — Install custom ASCII art MOTD on Ubuntu
#

set -euo pipefail

MOTD_DIR="/etc/update-motd.d"
TARGET="${MOTD_DIR}/00-header"

echo "Installing figlet..."
apt-get install -y figlet

echo "Backing up original header..."
cp "${TARGET}" "${TARGET}.bak"

echo "Writing new MOTD header..."
cat > "${TARGET}" << 'MOTD_SCRIPT'
#!/bin/bash
#
#  00-header — Custom MOTD: ASCII art banner with system stats
#

# ── Colours ──────────────────────────────────────────────────────────────────
CY='\033[0;36m'   # cyan
GR='\033[0;32m'   # green
YL='\033[1;33m'   # yellow
WH='\033[1;37m'   # bold white
DM='\033[2;37m'   # dim white
NC='\033[0m'      # reset

# ── Stats ─────────────────────────────────────────────────────────────────────
DATE=$(date '+%A, %d %B %Y')
TIME=$(date '+%H:%M:%S %Z')
UPTIME=$(uptime -p | sed 's/^up //')
LOAD=$(awk '{print $1", "$2", "$3}' /proc/loadavg)
CPUS=$(nproc)
HOST=$(hostname -s)
FQDN=$(hostname -f)

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""

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
    printf "${CY}\n"
    printf "    %s\n" "${TOP}"
    printf "    %s\n" "${MID}"
    printf "    %s\n" "${BOT}"
    printf "${NC}\n"
fi

# ── Divider ───────────────────────────────────────────────────────────────────
printf "${DM}  %s${NC}\n" "$(printf '─%.0s' {1..72})"

# ── Stats block ───────────────────────────────────────────────────────────────
printf "  ${YL}%-16s${NC} ${WH}%s${NC}\n"  "Date"         "${DATE}"
printf "  ${YL}%-16s${NC} ${WH}%s${NC}\n"  "Time"         "${TIME}"
printf "  ${YL}%-16s${NC} ${WH}%s${NC}\n"  "Uptime"       "${UPTIME}"
printf "  ${YL}%-16s${NC} ${WH}%s${NC}  ${DM}(%s CPU cores)${NC}\n" \
                                            "Load average" "${LOAD}" "${CPUS}"
printf "  ${YL}%-16s${NC} ${GR}%s${NC}\n"  "Hostname"     "${FQDN}"

# ── Footer divider ────────────────────────────────────────────────────────────
printf "${DM}  %s${NC}\n\n" "$(printf '─%.0s' {1..72})"
MOTD_SCRIPT

chmod 755 "${TARGET}"

echo "Disabling noisy MOTD scripts..."
chmod -x \
    "${MOTD_DIR}/50-landscape-sysinfo" \
    "${MOTD_DIR}/50-motd-news" \
    "${MOTD_DIR}/10-help-text" \
    2>/dev/null || true

echo ""
echo "Done. Preview:"
echo "────────────────────────────────────────"
run-parts --loglevel=0 "${MOTD_DIR}" 2>/dev/null || bash "${TARGET}"
