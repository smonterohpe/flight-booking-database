#!/bin/bash
# =============================================================================
# restore_postgres.sh — Restaura PostgreSQL desde el backup local (Plan B)
#
# USO: ./restore_postgres.sh
# NOTA: El camino principal de recuperación es Zerto. Usa este script
#       para resetear el entorno tras la demo.
# =============================================================================

set -euo pipefail

PGDATA="/var/lib/postgresql/16/main"
BACKUP_DIR="$(dirname "$0")/backup"
SERVICE_PG="postgresql"
PG_USER="postgres"

GRN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[1;33m'
CYA='\033[0;36m'; BLD='\033[1m'; RST='\033[0m'

typewriter() {
  local text="$1"; local delay="${2:-0.03}"
  for (( i=0; i<${#text}; i++ )); do
    printf '%s' "${text:$i:1}"; sleep "$delay"
  done; echo
}

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}ERROR: Ejecuta como root.${RST}"; exit 1
fi
if [ ! -d "$BACKUP_DIR/main" ]; then
  echo -e "${RED}ERROR: No se encuentra backup en $BACKUP_DIR/main${RST}"; exit 1
fi

clear
sleep 0.3
echo -e "${GRN}${BLD}"
cat << 'HERO_ART'

    ███████╗███████╗██████╗ ████████╗ ██████╗ 
    ╚══███╔╝██╔════╝██╔══██╗╚══██╔══╝██╔═══██╗
      ███╔╝ █████╗  ██████╔╝   ██║   ██║   ██║
     ███╔╝  ██╔══╝  ██╔══██╗   ██║   ██║   ██║
    ███████╗███████╗██║  ██║   ██║   ╚██████╔╝
    ╚══════╝╚══════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ 

               R E C O V E R Y   M O D E

HERO_ART
echo -e "${RST}"
sleep 0.4
typewriter "  Wario thought he won... but Zerto was watching." 0.04
sleep 0.3
typewriter "  Initiating local backup restore — plan B activated." 0.04
sleep 0.6
echo ""

BACKUP_SIZE=$(du -sh "$BACKUP_DIR/main" | awk '{print $1}')

# ── [1/5] Para PostgreSQL ─────────────────────────────────────────────────────
echo -e "${BLD}[1/5]${RST} Stopping PostgreSQL..."
systemctl stop "$SERVICE_PG" 2>/dev/null || true
sleep 2
echo -e "      ${GRN}✔ Stopped${RST}"

# ── [2/5] Elimina los datos cifrados ─────────────────────────────────────────
echo -e "\n${BLD}[2/5]${RST} Removing Wario's encrypted files..."
SIZE_BEFORE=$(du -sh "$PGDATA" 2>/dev/null | awk '{print $1}' || echo "?")
rm -rf "$PGDATA"
echo -e "      ${GRN}✔ Encrypted data removed ($SIZE_BEFORE deleted)${RST}"

# ── [3/5] Restaura desde backup ──────────────────────────────────────────────
echo -e "\n${BLD}[3/5]${RST} Restoring clean data from backup (~$BACKUP_SIZE)..."
(cp -a "$BACKUP_DIR/main" "$PGDATA") &
CP_PID=$!
while kill -0 "$CP_PID" 2>/dev/null; do
  for c in '⣾' '⣷' '⣯' '⣟' '⡿' '⢿' '⣻' '⣽'; do
    printf "\r      %s Copying..." "$c"; sleep 0.1
  done
done
wait "$CP_PID"
echo -e "\r      ${GRN}✔ Data restored to $PGDATA${RST}                    "

# ── [4/5] Restaura permisos ───────────────────────────────────────────────────
echo -e "\n${BLD}[4/5]${RST} Restoring PostgreSQL permissions..."
chown -R "$PG_USER:$PG_USER" "$PGDATA"
chmod 700 "$PGDATA"
echo -e "      ${GRN}✔ Permissions restored (owner: $PG_USER)${RST}"

# ── [5/5] Arranca PostgreSQL y verifica ──────────────────────────────────────
echo -e "\n${BLD}[5/5]${RST} Starting PostgreSQL..."
systemctl start "$SERVICE_PG"
sleep 4
if su -c "psql -d flight_booking -c 'SELECT 1;' -q -t" "$PG_USER" > /dev/null 2>&1; then
  echo -e "      ${GRN}✔ PostgreSQL responding (SELECT 1 OK)${RST}"
else
  echo -e "      ${RED}✗ PostgreSQL started but not responding — check logs:${RST}"
  echo -e "        journalctl -u postgresql -n 30 --no-pager"
  exit 1
fi

# ── Limpieza del backup ───────────────────────────────────────────────────────
echo ""
read -rp "  Delete local backup? (recommended after verifying recovery) [s/N]: " CONFIRM
if [[ "$CONFIRM" =~ ^[sS]$ ]]; then
  rm -rf "$BACKUP_DIR"
  echo -e "      ${GRN}✔ Backup deleted${RST}"
else
  echo -e "      ${YEL}Backup kept at $BACKUP_DIR${RST}"
fi

# ── Pantalla final ────────────────────────────────────────────────────────────
clear
sleep 0.3
echo -e "${GRN}${BLD}"
cat << 'VICTORY_ART'

    ██████╗ ███████╗ ██████╗ ██████╗ ██╗   ██╗███████╗██████╗ ██╗
    ██╔══██╗██╔════╝██╔════╝██╔═══██╗██║   ██║██╔════╝██╔══██╗██║
    ██████╔╝█████╗  ██║     ██║   ██║██║   ██║█████╗  ██████╔╝██║
    ██╔══██╗██╔══╝  ██║     ██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗╚═╝
    ██║  ██║███████╗╚██████╗╚██████╔╝ ╚████╔╝ ███████╗██║  ██║██╗
    ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═╝

VICTORY_ART
echo -e "${RST}"
sleep 0.4
typewriter "  Wario has been defeated. The data is SAFE." 0.04
sleep 0.3
typewriter "  The flight booking system is back online." 0.04
sleep 0.3
typewriter "  No coins were paid to Wario. WAH!" 0.04
sleep 0.5
echo ""
echo -e "${GRN}${BLD}═══════════════════════════════════════════════════${RST}"
echo -e "  Database   : ${GRN}RESTORED & OPERATIONAL${RST}"
echo -e "  Data loss  : ${GRN}ZERO (pre-attack backup)${RST}"
echo -e "  Wario paid : ${GRN}NOTHING${RST}"
echo -e "${GRN}${BLD}═══════════════════════════════════════════════════${RST}"
echo ""
echo -e "${YEL}  NOTE: Start the backend manually on its VM:${RST}"
echo -e "  ssh root@BACKEND_IP 'systemctl start flight-booking-backend'"
echo -e "${GRN}${BLD}═══════════════════════════════════════════════════${RST}"
echo ""
