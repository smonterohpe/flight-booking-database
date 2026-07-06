"""
sys-probe
=========
Microservicio mínimo que expone métricas de sistema (CPU, RAM, disco,
uptime) de la VM en la que corre. Se despliega tanto en la VM de
frontend como en la VM de base de datos, y lo consulta la
Observability Console a través de su NGINX (rutas /check/*-sys/).

Ejecutar con:
    uvicorn main:app --host 0.0.0.0 --port 5001
"""
import time

import psutil
from fastapi import FastAPI

app = FastAPI(title="sys-probe")

_BOOT_TIME = psutil.boot_time()


@app.get("/metrics")
async def metrics() -> dict:
    disk = psutil.disk_usage("/")
    mem = psutil.virtual_memory()

    return {
        "cpu_percent": psutil.cpu_percent(interval=0.2),
        "ram_used_mb": round((mem.total - mem.available) / (1024 * 1024), 1),
        "ram_total_mb": round(mem.total / (1024 * 1024), 1),
        "disk_used_gb": round(disk.used / (1024 ** 3), 1),
        "disk_total_gb": round(disk.total / (1024 ** 3), 1),
        "uptime_seconds": int(time.time() - _BOOT_TIME),
    }


@app.get("/ping")
async def ping() -> dict:
    return {"message": "pong"}
