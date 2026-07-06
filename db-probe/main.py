"""
db-probe
========
Microservicio mínimo que expone:
  - GET /ping    -> comprobación real "SELECT 1" contra PostgreSQL
  - GET /metrics -> conexiones, tamaño de BD, cache hit ratio, transacciones

Se despliega en la misma VM que PostgreSQL, y lo consulta la
Observability Console a través de su NGINX (ruta /check/db/).

Requiere un usuario de solo lectura con el rol `pg_monitor` para poder
leer las vistas pg_stat_* sin ser superusuario:

    CREATE ROLE probe_user WITH LOGIN PASSWORD '...';
    GRANT pg_monitor TO probe_user;
    GRANT CONNECT ON DATABASE flight_booking TO probe_user;

Ejecutar con:
    uvicorn main:app --host 0.0.0.0 --port 5000
"""
import os

import psycopg2
from fastapi import FastAPI, HTTPException

app = FastAPI(title="db-probe")

DATABASE_DSN = os.environ.get(
    "PROBE_DATABASE_DSN",
    "postgresql://probe_user:CHANGE_ME@localhost:5432/flight_booking",
)


def _connect():
    return psycopg2.connect(DATABASE_DSN, connect_timeout=3)


@app.get("/ping")
async def ping() -> dict:
    try:
        conn = _connect()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                cur.fetchone()
        finally:
            conn.close()
        return {"status": "ok", "message": "SELECT 1 succeeded"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Database unreachable: {exc}")


@app.get("/metrics")
async def metrics() -> dict:
    try:
        conn = _connect()
        try:
            with conn.cursor() as cur:
                cur.execute("SHOW max_connections;")
                max_connections = int(cur.fetchone()[0])

                cur.execute("SELECT count(*) FROM pg_stat_activity;")
                total_connections = cur.fetchone()[0]

                cur.execute(
                    "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"
                )
                active_connections = cur.fetchone()[0]

                cur.execute(
                    "SELECT pg_database_size(current_database());"
                )
                db_size_bytes = cur.fetchone()[0]

                cur.execute("""
                    SELECT
                        sum(blks_hit) AS hits,
                        sum(blks_hit) + sum(blks_read) AS total
                    FROM pg_stat_database;
                """)
                hits, total = cur.fetchone()
                cache_hit_ratio = round((hits / total) * 100, 1) if total else 0.0

                cur.execute("""
                    SELECT sum(xact_commit) + sum(xact_rollback)
                    FROM pg_stat_database;
                """)
                transactions = cur.fetchone()[0]
        finally:
            conn.close()

        return {
            "max_connections": max_connections,
            "total_connections": total_connections,
            "active_connections": active_connections,
            "connections_percent": round((total_connections / max_connections) * 100, 1),
            "db_size_mb": round(db_size_bytes / (1024 * 1024), 1),
            "cache_hit_ratio_percent": cache_hit_ratio,
            "transactions": int(transactions or 0),
        }
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Database unreachable: {exc}")
