#!/bin/bash
# update-motd.sh — Writes the custom MOTD 00-header and fixes PAM config
# Run as: bash update-motd.sh

set -euo pipefail

TARGET="/etc/update-motd.d/00-header"

# ── 1. Write the new 00-header ─────────────────────────────────────────────────
sudo tee "${TARGET}" > /dev/null << 'EOF'
#!/bin/bash
#
#  00-header — Custom MOTD: ASCII art banner with system stats and weather
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

# ── Memory ────────────────────────────────────────────────────────────────────
read -r MEM_TOTAL MEM_FREE MEM_AVAIL BUFFERS CACHED SWAP_TOTAL SWAP_FREE COMMIT_AS COMMIT_LIMIT <<< \
    $(awk '/^MemTotal:/{mt=$2} /^MemFree:/{mf=$2} /^MemAvailable:/{ma=$2}
           /^Buffers:/{bu=$2} /^Cached:/{ca=$2}
           /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
           /^Committed_AS:/{cas=$2} /^CommitLimit:/{cl=$2}
           END{print mt,mf,ma,bu,ca,st,sf,cas,cl}' /proc/meminfo)

MEM_USED_PCT=$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))
MEM_FREE_PCT=$(( MEM_FREE   * 100 / MEM_TOTAL ))
MEM_CACHED_PCT=$(( (CACHED + BUFFERS) * 100 / MEM_TOTAL ))
COMMIT_PCT=$(( COMMIT_AS * 100 / COMMIT_LIMIT ))
[[ "${SWAP_TOTAL}" -gt 0 ]] && SWAP_PCT=$(( (SWAP_TOTAL - SWAP_FREE) * 100 / SWAP_TOTAL )) || SWAP_PCT=0

printf "  ${YL}%-16s${NC} Used: ${WH}%s%%${NC}  Free: ${WH}%s%%${NC}  Cached: ${WH}%s%%${NC}  Committed: ${WH}%s%%${NC}  Swap: ${WH}%s%%${NC}\n" \
    "Memory" "${MEM_USED_PCT}" "${MEM_FREE_PCT}" "${MEM_CACHED_PCT}" "${COMMIT_PCT}" "${SWAP_PCT}"

# ── Weather ───────────────────────────────────────────────────────────────────
WEATHER=$(curl -s --connect-timeout 4 --max-time 6 "wttr.in/Mountain+Ash,Wales?format=3" 2>/dev/null)
if [ -n "${WEATHER}" ]; then
    printf "  ${YL}%-16s${NC} ${WH}%s${NC}\n" "Weather" "${WEATHER}"
else
    printf "  ${YL}%-16s${NC} ${DM}%s${NC}\n" "Weather" "(unavailable)"
fi

# ── Footer divider ────────────────────────────────────────────────────────────
printf "${DM}  %s${NC}\n\n" "$(printf '─%.0s' {1..72})"
EOF

sudo chmod 755 "${TARGET}"

# ── 2. Clear static /etc/motd so it doesn't pollute the output ────────────────
if [ -s /etc/motd ]; then
    sudo truncate -s 0 /etc/motd
    echo "Cleared static /etc/motd"
fi

# ── 3. Preview ────────────────────────────────────────────────────────────────
echo ""
echo "Preview:"
echo "────────────────────────────────────────"
sudo run-parts /etc/update-motd.d/
echo ""
echo "Done. The above is what you will see on next login."
