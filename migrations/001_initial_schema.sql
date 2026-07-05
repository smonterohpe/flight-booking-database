-- =====================================================================
-- Flight Booking Simulator - Esquema inicial de base de datos
-- Motor: PostgreSQL 14+
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Extensiones
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- para gen_random_uuid()

-- ---------------------------------------------------------------------
-- Tipos enumerados
-- ---------------------------------------------------------------------
CREATE TYPE booking_status AS ENUM ('PENDING', 'CONFIRMED', 'CANCELLED');
CREATE TYPE flight_status  AS ENUM ('SCHEDULED', 'DELAYED', 'CANCELLED', 'DEPARTED', 'LANDED');

-- ---------------------------------------------------------------------
-- Tabla: airports
-- Catálogo de aeropuertos de origen/destino
-- ---------------------------------------------------------------------
CREATE TABLE airports (
    id          SERIAL PRIMARY KEY,
    iata_code   CHAR(3) NOT NULL UNIQUE,
    name        VARCHAR(150) NOT NULL,
    city        VARCHAR(100) NOT NULL,
    country     VARCHAR(100) NOT NULL,
    timezone    VARCHAR(50)  NOT NULL DEFAULT 'UTC',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Tabla: seat_classes
-- Clases de asiento disponibles (turista, business, ...)
-- ---------------------------------------------------------------------
CREATE TABLE seat_classes (
    id               SERIAL PRIMARY KEY,
    code             VARCHAR(20) NOT NULL UNIQUE,   -- 'TOURIST', 'BUSINESS'
    name             VARCHAR(50) NOT NULL,          -- 'Turista', 'Business'
    price_multiplier NUMERIC(4,2) NOT NULL DEFAULT 1.00
);

-- ---------------------------------------------------------------------
-- Tabla: customers
-- Clientes que realizan reservas
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    id           SERIAL PRIMARY KEY,
    full_name    VARCHAR(150) NOT NULL,
    email        VARCHAR(150) NOT NULL UNIQUE,
    phone        VARCHAR(30),
    document_id  VARCHAR(30) NOT NULL UNIQUE,   -- DNI/pasaporte
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Tabla: flights
-- Catálogo de vuelos/rutas programados. El generador de reservas (RBG)
-- selecciona vuelos existentes de esta tabla para crear reservas.
-- ---------------------------------------------------------------------
CREATE TABLE flights (
    id                  SERIAL PRIMARY KEY,
    flight_number       VARCHAR(10) NOT NULL,          -- 'IB3456'
    airline_code        VARCHAR(3)  NOT NULL,           -- 'IB', 'FR', 'VY'
    airline_name        VARCHAR(100) NOT NULL,
    origin_airport_id      INTEGER NOT NULL REFERENCES airports(id),
    destination_airport_id INTEGER NOT NULL REFERENCES airports(id),
    departure_time      TIMESTAMPTZ NOT NULL,
    arrival_time        TIMESTAMPTZ NOT NULL,
    aircraft_type       VARCHAR(50),
    base_price          NUMERIC(10,2) NOT NULL CHECK (base_price >= 0),
    total_seats         INTEGER NOT NULL CHECK (total_seats > 0),
    status              flight_status NOT NULL DEFAULT 'SCHEDULED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_diff_airports CHECK (origin_airport_id <> destination_airport_id),
    CONSTRAINT chk_arrival_after_departure CHECK (arrival_time > departure_time)
);

-- ---------------------------------------------------------------------
-- Tabla: bookings
-- Reservas de billetes. Es la tabla "de actividad" sobre la que el
-- generador aleatorio de reservas (RBG) escribe continuamente, y sobre
-- la que la Observability Console calculará los KPIs en tiempo real.
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
    id                 BIGSERIAL PRIMARY KEY,
    booking_reference  VARCHAR(10) NOT NULL UNIQUE DEFAULT upper(substr(md5(gen_random_uuid()::text), 1, 8)),
    customer_id        INTEGER NOT NULL REFERENCES customers(id),
    flight_id          INTEGER NOT NULL REFERENCES flights(id),
    seat_class_id      INTEGER NOT NULL REFERENCES seat_classes(id),
    seat_number        VARCHAR(5),                       -- '14A'
    price              NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    status             booking_status NOT NULL DEFAULT 'CONFIRMED',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Trigger genérico para mantener updated_at en bookings
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bookings_updated_at
    BEFORE UPDATE ON bookings
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------
-- Índices de rendimiento
-- Pensados para las consultas típicas del dashboard: series temporales,
-- filtrado por vuelo/estado y búsquedas por cliente.
-- ---------------------------------------------------------------------
CREATE INDEX idx_bookings_created_at   ON bookings (created_at);
CREATE INDEX idx_bookings_flight_id    ON bookings (flight_id);
CREATE INDEX idx_bookings_customer_id  ON bookings (customer_id);
CREATE INDEX idx_bookings_status       ON bookings (status);
CREATE INDEX idx_flights_departure     ON flights (departure_time);
CREATE INDEX idx_flights_route         ON flights (origin_airport_id, destination_airport_id);

COMMIT;
