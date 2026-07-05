-- =====================================================================
-- Datos semilla: catálogo de vuelos de ejemplo
-- Las fechas se calculan de forma relativa a la fecha de carga para que
-- el catálogo siempre tenga vuelos "vigentes" con los que trabajar el
-- generador aleatorio de reservas (RBG), independientemente de cuándo
-- se ejecute este script.
-- =====================================================================

WITH a AS (
    SELECT iata_code, id FROM airports
)
INSERT INTO flights (flight_number, airline_code, airline_name, origin_airport_id, destination_airport_id,
                      departure_time, arrival_time, aircraft_type, base_price, total_seats, status)
SELECT
    'IB' || (1000 + s)::text,
    'IB',
    'Iberia',
    o.id,
    d.id,
    now() + (s || ' hours')::interval,
    now() + (s || ' hours')::interval + interval '2 hours 15 minutes',
    'Airbus A320',
    (90 + (s % 5) * 20)::numeric,
    180,
    'SCHEDULED'
FROM generate_series(1, 40) AS s
JOIN a AS o ON o.iata_code = (ARRAY['MAD','BCN','LIS','MAD','FRA'])[1 + (s % 5)]
JOIN a AS d ON d.iata_code = (ARRAY['CDG','LHR','FCO','AMS','JFK'])[1 + (s % 5)]
WHERE o.iata_code <> d.iata_code;

WITH a AS (
    SELECT iata_code, id FROM airports
)
INSERT INTO flights (flight_number, airline_code, airline_name, origin_airport_id, destination_airport_id,
                      departure_time, arrival_time, aircraft_type, base_price, total_seats, status)
SELECT
    'VY' || (2000 + s)::text,
    'VY',
    'Vueling',
    o.id,
    d.id,
    now() + (s || ' hours')::interval,
    now() + (s || ' hours')::interval + interval '1 hour 45 minutes',
    'Airbus A319',
    (60 + (s % 4) * 15)::numeric,
    144,
    'SCHEDULED'
FROM generate_series(1, 30) AS s
JOIN a AS o ON o.iata_code = (ARRAY['BCN','MAD','LIS'])[1 + (s % 3)]
JOIN a AS d ON d.iata_code = (ARRAY['FCO','AMS','CDG'])[1 + (s % 3)]
WHERE o.iata_code <> d.iata_code;
