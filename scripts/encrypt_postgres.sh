#!/bin/bash
# =============================================================================
# encrypt_postgres.sh — Simulación de ataque de ransomware por WARIO
# =============================================================================

set -euo pipefail

# ── Configuración ─────────────────────────────────────────────────────────────
PGDATA="/var/lib/postgresql/16/main"
BACKUP_DIR="$(dirname "$0")/backup"
SERVICE_PG="postgresql"
PADDING_COUNT=5
PADDING_SIZE_MB=512
ENCRYPT_KEY="wario-ransom-demo-2026"

# ── Colores ───────────────────────────────────────────────────────────────────
YEL='\033[1;33m'; RED='\033[0;31m'; GRN='\033[0;32m'
CYA='\033[0;36m'; MAG='\033[0;35m'; BLD='\033[1m'; RST='\033[0m'
BLK_BG='\033[40m'; YEL_BG='\033[43m'

# ── Efecto de escritura animada ───────────────────────────────────────────────
typewriter() {
  local text="$1"
  local delay="${2:-0.035}"
  for (( i=0; i<${#text}; i++ )); do
    printf '%s' "${text:$i:1}"
    sleep "$delay"
  done
  echo
}

blink_warning() {
  for _ in 1 2 3; do
    printf "${RED}${BLD}██ ALERT ██${RST}"
    sleep 0.3
    printf "\r           \r"
    sleep 0.2
  done
}

# ── Comprobaciones previas (silenciosas, antes de la animación) ───────────────
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}ERROR: Ejecuta como root.${RST}"; exit 1
fi
if [ ! -d "$PGDATA" ]; then
  echo -e "${RED}ERROR: No se encuentra PGDATA en $PGDATA${RST}"; exit 1
fi
if [ -d "$BACKUP_DIR" ]; then
  echo -e "${RED}ERROR: Ya existe backup en $BACKUP_DIR. Ejecuta restore_postgres.sh primero.${RST}"; exit 1
fi
PGDATA_SIZE_MB=$(du -sm "$PGDATA" | awk '{print $1}')
FREE_MB=$(df -m "$PGDATA" | awk 'NR==2{print $4}')
NEEDED_MB=$((PGDATA_SIZE_MB + PADDING_COUNT * PADDING_SIZE_MB + 1024))
if [ "$FREE_MB" -lt "$NEEDED_MB" ]; then
  echo -e "${RED}ERROR: Espacio insuficiente. Necesario: ~${NEEDED_MB}MB | Libre: ${FREE_MB}MB${RST}"; exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
#   W A R I O   A P P E A R S
# ─────────────────────────────────────────────────────────────────────────────
clear
sleep 0.5

echo -e "${YEL}${BLD}"
cat << 'WARIO_ART'

        ██╗    ██╗ █████╗ ██████╗ ██╗ ██████╗ 
        ██║    ██║██╔══██╗██╔══██╗██║██╔═══██╗
        ██║ █╗ ██║███████║██████╔╝██║██║   ██║
        ██║███╗██║██╔══██║██╔══██╗██║██║   ██║
        ╚███╔███╔╝██║  ██║██║  ██║██║╚██████╔╝
         ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝ ╚═════╝ 

WARIO_ART
echo -e "${RST}"

sleep 0.4
echo -e "${YEL}${BLD}          R A N S O M W A R E   v2.0${RST}"
echo -e "${YEL}             by Wario Industries™${RST}"
echo ""
sleep 0.8

typewriter "  WAH HA HA! Is-a me, WARIO!" 0.06
sleep 0.3
typewriter "  You think your little airline database is safe?" 0.04
sleep 0.2
typewriter "  WRONG! Wario is the best at EVERYTHING." 0.04
sleep 0.3
typewriter "  Even ransomware. ESPECIALLY ransomware." 0.04
sleep 0.5
echo ""
typewriter "  Now Wario takes your precious data..." 0.04
sleep 0.2
typewriter "  ...and you pay Wario MANY coins to get it back. WAH!" 0.04
sleep 0.8

echo ""
blink_warning
echo ""
sleep 0.3

# ── [1/5] Backup del directorio de datos ──────────────────────────────────────
echo -e "\n${YEL}${BLD}[1/5]${RST} ${BLD}Making backup before encryption...${RST}"
echo -ne "      "
mkdir -p "$BACKUP_DIR"
(cp -a "$PGDATA" "$BACKUP_DIR/main" && chown -R root:root "$BACKUP_DIR") &
CP_PID=$!
while kill -0 "$CP_PID" 2>/dev/null; do
  for c in '⣾' '⣷' '⣯' '⣟' '⡿' '⢿' '⣻' '⣽'; do
    printf "\r      %s Copying PGDATA (~%s MB)..." "$c" "$PGDATA_SIZE_MB"
    sleep 0.1
  done
done
wait "$CP_PID"
echo -e "\r      ${GRN}✔ Backup saved → $BACKUP_DIR/main${RST}           "

# ── [2/5] Para PostgreSQL ─────────────────────────────────────────────────────
echo -e "\n${YEL}${BLD}[2/5]${RST} ${BLD}Stopping PostgreSQL...${RST}"
echo -ne "      "
systemctl stop "$SERVICE_PG"
echo -e "${GRN}✔ PostgreSQL stopped — database going dark!${RST}"
sleep 0.5

# ── [3/5] Cifra WAL ───────────────────────────────────────────────────────────
echo -e "\n${YEL}${BLD}[3/5]${RST} ${BLD}WARIO encrypts your WAL files!${RST}"
WAL_DIR="$PGDATA/pg_wal"
WAL_COUNT=0
if [ -d "$WAL_DIR" ]; then
  while IFS= read -r -d '' wal_file; do
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
      -in "$wal_file" -out "${wal_file}.wario" \
      -k "$ENCRYPT_KEY" 2>/dev/null
    rm -f "$wal_file"
    WAL_COUNT=$((WAL_COUNT + 1))
    printf "\r      ${RED}🔒 Encrypting WAL: %d files...${RST}" "$WAL_COUNT"
  done < <(find "$WAL_DIR" -maxdepth 1 -type f -print0)
fi
echo -e "\n      ${GRN}✔ $WAL_COUNT WAL files encrypted (WAH!)${RST}"

# ── [4/5] Renombra ficheros de datos ─────────────────────────────────────────
echo -e "\n${YEL}${BLD}[4/5]${RST} ${BLD}WARIO scrambles your data files!${RST}"
BASE_DIR="$PGDATA/base"
RENAMED=0
if [ -d "$BASE_DIR" ]; then
  while IFS= read -r -d '' db_file; do
    mv "$db_file" "${db_file}.wario"
    RENAMED=$((RENAMED + 1))
    if (( RENAMED % 50 == 0 )); then
      printf "\r      ${RED}🔒 Files encrypted: %d...${RST}" "$RENAMED"
    fi
  done < <(find "$BASE_DIR" -maxdepth 2 -type f \
    -not -name "*.wario" -print0)
fi
echo -e "\n      ${GRN}✔ $RENAMED data files encrypted${RST}"

# ── [5/5] Padding ────────────────────────────────────────────────────────────
echo -e "\n${YEL}${BLD}[5/5]${RST} ${BLD}WARIO fills your disk with garbage! WAH!${RST}"
PADDING_DIR="$PGDATA/pg_tblspc"
mkdir -p "$PADDING_DIR"
for i in $(seq 1 $PADDING_COUNT); do
  printf "\r      ${RED}💣 Generating chaos file %d/%d (%d MB)...${RST}" \
    "$i" "$PADDING_COUNT" "$PADDING_SIZE_MB"
  dd if=/dev/urandom \
     of="$PADDING_DIR/wario_chaos_${i}.enc" \
     bs=1M count="$PADDING_SIZE_MB" \
     status=none 2>/dev/null
done
echo -e "\n      ${GRN}✔ $((PADDING_COUNT * PADDING_SIZE_MB)) MB of chaos deployed${RST}"

# ── Nota de rescate al estilo Wario ──────────────────────────────────────────
cat > "$PGDATA/README_WARIO.txt" << 'RANSOM_NOTE'

 ██╗    ██╗ █████╗ ██████╗ ██╗ ██████╗     ██╗    ██╗ █████╗ ███████╗
 ██║    ██║██╔══██╗██╔══██╗██║██╔═══██╗    ██║    ██║██╔══██╗██╔════╝
 ██║ █╗ ██║███████║██████╔╝██║██║   ██║    ██║ █╗ ██║███████║███████╗
 ██║███╗██║██╔══██║██╔══██╗██║██║   ██║    ██║███╗██║██╔══██║╚════██║
 ╚███╔███╔╝██║  ██║██║  ██║██║╚██████╔╝    ╚███╔███╔╝██║  ██║███████║
  ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝ ╚═════╝     ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝
                               H E R E

══════════════════════════════════════════════════════════════════

  WAH HA HA! Is-a me, WARIO!

  Your pathetic little flight booking database belongs to WARIO now.
  All your reservations, all your revenue, all your precious data —
  ENCRYPTED. By the greatest villain in the world. Me. WARIO.

  HOW TO GET YOUR DATA BACK:
  ──────────────────────────
  Send 50,000 Gold Coins (or 2 BTC, Wario accepts both) to:

      👛 bc1q_WARIO_WANTS_YOUR_COINS_wah_ha_ha_q0xkz

  Then email proof to: wario@waluigi-industries.evil

  WARNING FROM WARIO:
  ───────────────────
  ✗ Do not try to restore from backup — Wario already checked.
  ✗ Do not call the police — they cannot catch Wario.
  ✗ Do not try to be clever — you are not as smart as Wario.
    (Nobody is as smart as Wario.)

  You have 72 hours. After that, Wario deletes the key.
  And buys more garlic with the proceeds. WAH!

  ── Wario, CEO of Wario Industries™ ──
    "It'sa not stealing if you're Wario."

══════════════════════════════════════════════════════════════════

    --- THIS IS A SECURITY DEMONSTRATION ---
    --- Run restore_postgres.sh to recover (Zerto is faster) ---

RANSOM_NOTE

# ── Pantalla final de Wario ───────────────────────────────────────────────────
clear
sleep 0.3
echo -e "${YEL}${BLD}"
cat << 'WARIO_WIN'

    ██╗    ██╗ █████╗ ██████╗ ██╗ ██████╗ 
    ██║    ██║██╔══██╗██╔══██╗██║██╔═══██╗
    ██║ █╗ ██║███████║██████╔╝██║██║   ██║
    ██║███╗██║██╔══██║██╔══██╗██║██║   ██║
    ╚███╔███╔╝██║  ██║██║  ██║██║╚██████╔╝
     ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝ ╚═════╝ 

              W I N S   A G A I N

WARIO_WIN
echo -e "${RST}"
sleep 0.5
typewriter "  WAH HA HA! Wario has encrypted EVERYTHING!" 0.05
sleep 0.2
typewriter "  Your database? GONE. Your revenue? MINE." 0.05
sleep 0.2
typewriter "  Your precious flight bookings? WARIO'S NOW!" 0.05
sleep 0.5
echo ""
typewriter "  Check README_WARIO.txt for payment instructions." 0.04
sleep 0.2
typewriter "  Or... use Zerto and recover in seconds. WAH!" 0.04
sleep 0.3
echo ""
echo -e "${RED}${BLD}═══════════════════════════════════════════════════${RST}"
echo -e "  Database  : ${RED}ENCRYPTED (.wario)${RST}"
echo -e "  WAL files : ${RED}ENCRYPTED (.wario)${RST}"
echo -e "  Disk      : ${RED}FILLING UP (${PADDING_COUNT}×${PADDING_SIZE_MB}MB chaos)${RST}"
echo -e "  Backup    : ${GRN}SAFE → $BACKUP_DIR/main${RST}"
echo -e "${RED}${BLD}═══════════════════════════════════════════════════${RST}"
echo ""
echo -e "${CYA}  RECOVERY OPTIONS:${RST}"
echo -e "  → ${BLD}Zerto failover${RST}  : Use the Observability Console (fastest)"
echo -e "  → ${BLD}Local backup${RST}    : ./restore_postgres.sh (plan B)"
echo -e "${RED}${BLD}═══════════════════════════════════════════════════${RST}"
echo ""
