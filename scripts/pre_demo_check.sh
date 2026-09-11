#!/bin/bash
# =============================================================================
# pre_demo_check.sh — Verifica que el entorno está listo para la demo
#
# Ejecutar en la VM de base de datos antes de empezar la demo.
# =============================================================================

PGDATA="/var/lib/postgresql/16/main"
BACKUP_DIR="$(dirname "$0")/backup"
BACKEND_HOST="10.10.44.14"
FRONTEND_HOST="10.10.44.13"

GRN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[1;33m'; BLD='\033[1m'; RST='\033[0m'
PASS=0; FAIL=0; WARN=0

ok()   { echo -e "  ${GRN}✔${RST}  $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✗${RST}  $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YEL}⚠${RST}  $1"; WARN=$((WARN+1)); }

echo -e "\n${BLD}═══ PRE-DEMO CHECK — FLIGHT BOOKING SIMULATOR ════${RST}\n"

# ── Base de datos ─────────────────────────────────────────────────────────────
echo -e "${BLD}[Base de datos]${RST}"
systemctl is-active postgresql > /dev/null 2>&1 \
  && ok "PostgreSQL activo" || fail "PostgreSQL NO está activo"

[ -d "$PGDATA" ] \
  && ok "PGDATA existe: $PGDATA" || fail "No se encuentra PGDATA"

su -c "psql -d flight_booking -c 'SELECT COUNT(*) FROM bookings;' -q -t" postgres > /dev/null 2>&1 \
  && ok "Base de datos 'flight_booking' responde" \
  || fail "No se puede consultar 'flight_booking'"

BOOKINGS=$(su -c "psql -d flight_booking -c 'SELECT COUNT(*) FROM bookings;' -q -t" postgres 2>/dev/null | tr -d ' ')
[ -n "$BOOKINGS" ] && ok "Reservas en BD: $BOOKINGS" || warn "No se pudo contar reservas"

[ ! -d "$BACKUP_DIR" ] \
  && ok "Sin backup previo (entorno limpio)" \
  || warn "Ya existe un backup en $BACKUP_DIR — ¿hay una demo sin restaurar?"

# Espacio disponible
FREE_GB=$(df -BG "$PGDATA" | awk 'NR==2{gsub("G","",$4); print $4}')
[ "$FREE_GB" -ge 5 ] \
  && ok "Espacio libre: ${FREE_GB} GB (suficiente para el ataque)" \
  || fail "Espacio libre insuficiente: ${FREE_GB} GB (necesitas al menos 5 GB)"

openssl version > /dev/null 2>&1 \
  && ok "openssl instalado" || fail "openssl NO instalado (apt install openssl)"

# ── Backend ───────────────────────────────────────────────────────────────────
echo -e "\n${BLD}[Backend]${RST}"
HEALTH=$(curl -s --max-time 5 "http://$BACKEND_HOST:8000/api/health" 2>/dev/null)
echo "$HEALTH" | grep -q '"status":"ok"' \
  && ok "Backend responde (health OK)" || fail "Backend no responde en $BACKEND_HOST:8000"

RBG=$(curl -s --max-time 5 "http://$BACKEND_HOST:8000/api/rbg/status" 2>/dev/null)
echo "$RBG" | grep -q '"running":true' \
  && ok "RBG activo (generando reservas)" \
  || warn "RBG no está activo — arrancarlo desde el frontend antes de la demo"

IN_BH=$(echo "$RBG" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('in_business_hours','?'))" 2>/dev/null)
[ "$IN_BH" = "True" ] \
  && ok "RBG en horario de negocio (generando)" \
  || warn "RBG fuera de horario de negocio (no generará reservas hasta las 08:00 UTC)"

# ── Frontend ──────────────────────────────────────────────────────────────────
echo -e "\n${BLD}[Frontend]${RST}"
curl -s --max-time 5 "http://$FRONTEND_HOST/" > /dev/null 2>&1 \
  && ok "Frontend accesible" || fail "Frontend no responde en $FRONTEND_HOST"

# ── Scripts ───────────────────────────────────────────────────────────────────
echo -e "\n${BLD}[Scripts de demo]${RST}"
[ -x "$(dirname "$0")/encrypt_postgres.sh" ] \
  && ok "encrypt_postgres.sh listo" || fail "encrypt_postgres.sh no encontrado o sin permisos"
[ -x "$(dirname "$0")/restore_postgres.sh" ] \
  && ok "restore_postgres.sh listo" || fail "restore_postgres.sh no encontrado o sin permisos"
[ -x "$(dirname "$0")/zerto_insert-checkpoint.sh" ] \
  && ok "zerto_insert-checkpoint.sh listo" \
  || warn "zerto_insert-checkpoint.sh no encontrado (necesario para el checkpoint pre-ataque)"

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo -e "─────────────────────────────────────────"
TOTAL=$((PASS+FAIL+WARN))
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo -e "${GRN}${BLD}✅ Entorno listo para la demo ($PASS/$TOTAL OK)${RST}"
elif [ "$FAIL" -eq 0 ]; then
  echo -e "${YEL}${BLD}⚠  Entorno casi listo — revisa los avisos ($WARN warnings, $PASS OK)${RST}"
else
  echo -e "${RED}${BLD}❌ Hay problemas que resolver antes de la demo ($FAIL fallos)${RST}"
fi
echo ""
