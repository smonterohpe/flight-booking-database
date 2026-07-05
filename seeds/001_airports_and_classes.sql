-- =====================================================================
-- Datos semilla: aeropuertos y clases de asiento
-- =====================================================================

INSERT INTO seat_classes (code, name, price_multiplier) VALUES
    ('TOURIST',  'Turista',  1.00),
    ('BUSINESS', 'Business', 2.50)
ON CONFLICT (code) DO NOTHING;

INSERT INTO airports (iata_code, name, city, country, timezone) VALUES
    ('MAD', 'Aeropuerto Adolfo Suárez Madrid-Barajas', 'Madrid',     'España',        'Europe/Madrid'),
    ('BCN', 'Aeropuerto de Barcelona-El Prat',          'Barcelona', 'España',        'Europe/Madrid'),
    ('LIS', 'Aeropuerto Humberto Delgado',              'Lisboa',    'Portugal',      'Europe/Lisbon'),
    ('CDG', 'Aeropuerto Charles de Gaulle',             'París',     'Francia',       'Europe/Paris'),
    ('LHR', 'Aeropuerto de Heathrow',                   'Londres',   'Reino Unido',   'Europe/London'),
    ('FCO', 'Aeropuerto Leonardo da Vinci',              'Roma',      'Italia',        'Europe/Rome'),
    ('AMS', 'Aeropuerto de Ámsterdam-Schiphol',          'Ámsterdam', 'Países Bajos',  'Europe/Amsterdam'),
    ('FRA', 'Aeropuerto de Fráncfort del Meno',          'Fráncfort', 'Alemania',      'Europe/Berlin'),
    ('JFK', 'Aeropuerto John F. Kennedy',                'Nueva York','Estados Unidos','America/New_York'),
    ('MEX', 'Aeropuerto Internacional de la Ciudad de México', 'Ciudad de México', 'México', 'America/Mexico_City')
ON CONFLICT (iata_code) DO NOTHING;
