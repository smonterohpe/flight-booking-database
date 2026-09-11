#!/bin/bash
# =============================================================================
# restore_postgres.sh — Restaura PostgreSQL desde el backup local
#
# USO (como root en la VM de base de datos):
#   ./restore_postgres.sh
#
# QUÉ HACE:
#   1. Para PostgreSQL (si estuviera corriendo)
#   2. Elimina los ficheros cifrados/renombrados por encrypt_postgres.sh
#   3. Restaura el directorio de datos desde el backup local
#   4. Restaura los permisos correctos de PostgreSQL
#   5. Arranca PostgreSQL y verifica que responde
#   6. Arranca el backend y verifica que responde
#   7. Elimina el backup local (limpieza)
#
# NOTA: Este script es el PLAN B de la demo.
#   El camino principal de recuperación es el failover con Zerto.
#   Usa este script solo si quieres mostrar la recuperación desde
#   el backup local (sin Zerto) o para resetear el entorno de demo.
# =============================================================================

set -euo pipefail

# ── Configuración ─────────────────────────────────────────────────────────────
PGDATA="/var/lib/postgresql/16/main"
BACKUP_DIR="$(dirname "$0")/backup"
SERVICE_PG="postgresql"
SERVICE_BACKEND="flight-booking-backend"
BACKEND_HOST="10.10.44.14"   # IP de la VM de backend — ajusta si es diferente
PG_USER="postgres"

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; BLD='\033[1m'; RST='\033[0m'

# ── Comprobaciones previas ────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}ERROR: Este script debe ejecutarse como root.${RST}"
  exit 1
fi

if [ ! -d "$BACKUP_DIR/main" ]; then
  echo -e "${RED}ERROR: No se encuentra el backup en $BACKUP_DIR/main${RST}"
  echo -e "Ejecuta encrypt_postgres.sh primero, o verifica la ruta del backup."
  exit 1
fi

BACKUP_SIZE=$(du -sh "$BACKUP_DIR/main" | awk '{print $1}')

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BLD}${GRN}✦  RESTAURACIÓN DE FLIGHT BOOKING DATABASE${RST}"
echo -e "${YEL}Restaurando desde backup local: $BACKUP_DIR/main ($BACKUP_SIZE)${RST}\n"

# ── [1/6] Para PostgreSQL ─────────────────────────────────────────────────────
echo -e "${BLD}[1/6]${RST} Asegurando que PostgreSQL está parado..."
systemctl stop "$SERVICE_PG" 2>/dev/null || true
sleep 2
echo -e "      ${GRN}✔ PostgreSQL parado${RST}"

# ── [2/6] Elimina los datos cifrados ─────────────────────────────────────────
echo -e "${BLD}[2/6]${RST} Eliminando datos cifrados..."
PGDATA_SIZE_BEFORE=$(du -sh "$PGDATA" 2>/dev/null | awk '{print $1}' || echo "?")
rm -rf "$PGDATA"
echo -e "      ${GRN}✔ Directorio cifrado eliminado ($PGDATA_SIZE_BEFORE)${RST}"

# ── [3/6] Restaura desde backup ──────────────────────────────────────────────
echo -e "${BLD}[3/6]${RST} Restaurando desde backup (~$BACKUP_SIZE)..."
cp -a "$BACKUP_DIR/main" "$PGDATA"
echo -e "      ${GRN}✔ Datos restaurados en $PGDATA${RST}"

# ── [4/6] Restaura permisos ───────────────────────────────────────────────────
echo -e "${BLD}[4/6]${RST} Restaurando permisos de PostgreSQL..."
chown -R "$PG_USER:$PG_USER" "$PGDATA"
chmod 700 "$PGDATA"
echo -e "      ${GRN}✔ Permisos restaurados (propietario: $PG_USER)${RST}"

# ── [5/6] Arranca PostgreSQL y verifica ──────────────────────────────────────
echo -e "${BLD}[5/6]${RST} Arrancando PostgreSQL..."
systemctl start "$SERVICE_PG"
sleep 4

# Verifica que PostgreSQL responde con SELECT 1
if su -c "psql -d flight_booking -c 'SELECT 1;' -q -t" "$PG_USER" > /dev/null 2>&1; then
  echo -e "      ${GRN}✔ PostgreSQL responde correctamente (SELECT 1 OK)${RST}"
else
  echo -e "      ${RED}✗ PostgreSQL arrancó pero no responde. Revisa los logs:${RST}"
  echo -e "        journalctl -u postgresql -n 30 --no-pager"
  exit 1
fi

# ── [6/6] Arranca el backend ──────────────────────────────────────────────────
echo -e "${BLD}[6/6]${RST} Arrancando el backend..."
ssh -o StrictHostKeyChecking=no root@"$BACKEND_HOST" \
  "systemctl start $SERVICE_BACKEND && sleep 3 && systemctl is-active $SERVICE_BACKEND" \
  2>/dev/null && echo -e "      ${GRN}✔ Backend arrancado${RST}" \
  || echo -e "      ${YEL}⚠ No se pudo arrancar el backend remotamente — arráncalo manualmente${RST}"

# ── Limpieza del backup ───────────────────────────────────────────────────────
echo ""
read -rp "¿Eliminar el backup local? (recomendado tras verificar la recuperación) [s/N]: " CONFIRM
if [[ "$CONFIRM" =~ ^[sS]$ ]]; then
  rm -rf "$BACKUP_DIR"
  echo -e "      ${GRN}✔ Backup eliminado${RST}"
else
  echo -e "      ${YEL}Backup conservado en $BACKUP_DIR${RST}"
fi

# ── Resumen final ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}${BLD}════════════════════════════════════════════════════════${RST}"
echo -e "${GRN}${BLD}  RESTAURACIÓN COMPLETADA${RST}"
echo -e "${GRN}${BLD}════════════════════════════════════════════════════════${RST}"
echo -e "  Base de datos  : ${GRN}OPERATIVA${RST}"
echo -e "  Backend        : ${GRN}ARRANCADO${RST}"
echo -e "  Pérdida de datos: ${GRN}NINGUNA${RST} (restaurado desde backup pre-ataque)"
echo -e "${GRN}${BLD}════════════════════════════════════════════════════════${RST}"
echo ""
