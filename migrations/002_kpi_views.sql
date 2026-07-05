-- =====================================================================
-- Vistas de apoyo para KPIs (consumidas por el Backend / Observability
-- Console). Se modelan sobre el mismo patrón que el dashboard de
-- "Pedidos" ya construido: total, ingresos, media/día, última reserva...
-- =====================================================================

BEGIN;

-- Reservas confirmadas por minuto, para gráficas de series temporales
CREATE OR REPLACE VIEW v_bookings_per_minute AS
SELECT
    date_trunc('minute', created_at) AS minute,
    COUNT(*)                         AS bookings_count,
    SUM(price)                       AS revenue
FROM bookings
WHERE status = 'CONFIRMED'
GROUP BY 1
ORDER BY 1;

-- Resumen global tipo "tarjetas KPI" del dashboard
CREATE OR REPLACE VIEW v_bookings_summary AS
SELECT
    COUNT(*)                                              AS total_bookings,
    COALESCE(SUM(price), 0)                                AS total_revenue,
    COALESCE(SUM(price) / NULLIF(COUNT(DISTINCT created_at::date), 0), 0) AS avg_revenue_per_day,
    COALESCE(COUNT(*)::numeric / NULLIF(COUNT(DISTINCT created_at::date), 0), 0) AS avg_bookings_per_day,
    MAX(created_at)                                        AS last_booking_at
FROM bookings
WHERE status = 'CONFIRMED';

COMMIT;
