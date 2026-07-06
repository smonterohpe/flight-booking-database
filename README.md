# flight-booking-database

Esquema y datos semilla de PostgreSQL para el **Flight Booking Simulator**,
usado en la demo de continuidad de negocio junto con:

- `flight-booking-frontend` — simulador de reservas (con RBG integrado)
- `flight-booking-backend` — API REST (FastAPI)
- `observability-console` — dashboard de KPIs y monitorización (con integración Zerto)

## Modelo de datos

```
airports  ──┐
            ├──< flights >──┐
            ┘               ├──< bookings >── customers
seat_classes ────────────────┘
```

| Tabla         | Descripción                                                |
|---------------|-------------------------------------------------------------|
| `airports`    | Catálogo de aeropuertos (origen/destino)                    |
| `seat_classes`| Clases de asiento (Turista, Business) y su multiplicador     |
| `customers`   | Clientes que realizan reservas                               |
| `flights`     | Catálogo de vuelos/rutas programados                          |
| `bookings`    | Reservas de billetes — tabla de actividad continua (RBG)      |

Vistas de apoyo para KPIs (`v_bookings_per_minute`, `v_bookings_summary`)
pensadas para alimentar directamente al backend/observability console,
replicando el patrón del dashboard de "Pedidos" ya construido.

## Requisitos

- PostgreSQL 14+
- Extensión `pgcrypto` (se crea automáticamente en la migración)

## Despliegue en la VM de base de datos

```bash
# 1. Instalar PostgreSQL (Ubuntu/Debian)
sudo apt update && sudo apt install -y postgresql postgresql-contrib

# 2. Crear base de datos y usuario de aplicación
sudo -u postgres psql -c "CREATE DATABASE flight_booking;"
sudo -u postgres psql -c "CREATE USER flight_app WITH PASSWORD 'CAMBIA_ESTA_PASSWORD';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE flight_booking TO flight_app;"

# 3. Aplicar migraciones (en orden)
psql -U flight_app -d flight_booking -h localhost -f migrations/001_initial_schema.sql
psql -U flight_app -d flight_booking -h localhost -f migrations/002_kpi_views.sql

# 4. Cargar datos semilla
psql -U flight_app -d flight_booking -h localhost -f seeds/001_airports_and_classes.sql
psql -U flight_app -d flight_booking -h localhost -f seeds/002_sample_flights.sql
```

### Permitir conexiones remotas desde la VM del backend

Editar `postgresql.conf`:
```
listen_addresses = '*'
```

Editar `pg_hba.conf` (ajustar el rango a la subred de tus VMs):
```
host    flight_booking    flight_app    10.0.0.0/24    scram-sha-256
```

Reiniciar el servicio:
```bash
sudo systemctl restart postgresql
```

## Notas para la demo de continuidad de negocio

- La tabla `bookings` es el punto crítico de "actividad de negocio": es
  sobre la que se medirá la pérdida/recuperación de datos ante una
  interrupción simulada.
- Las vistas de KPI están diseñadas para que la Observability Console
  pueda calcular el equivalente a "Total Reservas", "Ingresos Totales",
  "Última reserva hace X" y la serie temporal de reservas/minuto, igual
  que en el dashboard de referencia (`Pedidos`).
- Pendiente (siguiente fase): estrategia de replicación/protección de
  datos (Zerto) sobre esta VM, que el backend expondrá a través de su
  API para que la consola de observabilidad la consuma.

## Servicios de monitorización (db-probe y sys-probe)

Además del esquema, este proyecto incluye dos microservicios ligeros
que se despliegan **en la misma VM que PostgreSQL** y que consulta la
Observability Console:

| Servicio    | Puerto | Endpoints                | Qué expone                                             |
|-------------|--------|---------------------------|---------------------------------------------------------|
| `db-probe`  | 5000   | `/ping`, `/metrics`        | SELECT 1 real, conexiones, tamaño BD, cache hit, transacciones |
| `sys-probe` | 5001   | `/ping`, `/metrics`        | CPU, RAM, disco, uptime de la VM                        |

### Despliegue de los probes

```bash
# Crear usuario de solo lectura para el probe (rol pg_monitor, sin superusuario)
sudo -u postgres psql -d flight_booking -c "
  CREATE ROLE probe_user WITH LOGIN PASSWORD 'CAMBIA_ESTA_PASSWORD';
  GRANT pg_monitor TO probe_user;
  GRANT CONNECT ON DATABASE flight_booking TO probe_user;
"

# Usuario de sistema para ambos servicios
sudo useradd -r -s /bin/false probe || true

# --- db-probe ---
sudo mkdir -p /opt/db-probe
sudo cp -r db-probe/* /opt/db-probe/
cd /opt/db-probe
sudo python3 -m venv venv
sudo ./venv/bin/pip install -r requirements.txt
sudo nano /opt/db-probe/db-probe.service   # ajustar PROBE_DATABASE_DSN
sudo cp db-probe.service /etc/systemd/system/

# --- sys-probe ---
sudo mkdir -p /opt/sys-probe
sudo cp -r ../sys-probe/* /opt/sys-probe/
cd /opt/sys-probe
sudo python3 -m venv venv
sudo ./venv/bin/pip install -r requirements.txt
sudo cp sys-probe.service /etc/systemd/system/

# Arrancar ambos
sudo chown -R probe:probe /opt/db-probe /opt/sys-probe
sudo systemctl daemon-reload
sudo systemctl enable --now db-probe sys-probe
```

Recuerda abrir los puertos 5000 y 5001 en el firewall de esta VM, pero
**solo hacia la VM de la Observability Console** (no expongas estos
puertos a internet).

## Próximos pasos

1. `flight-booking-backend`: API REST sobre este esquema (FastAPI + SQLAlchemy/asyncpg)
2. `flight-booking-frontend`: UI + generador aleatorio de reservas (RBG)
3. `observability-console`: dashboard de KPIs + estado de sistemas + Zerto
