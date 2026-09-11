# Guía de demo — Ransomware & Continuidad de Negocio
## Flight Booking Simulator · Zerto

---

## Narrativa

> "Nuestro simulador de reservas de vuelos lleva horas operando con
> actividad continua. En un momento dado, la base de datos sufre un
> ataque de ransomware. Gracias a Zerto, recuperamos la operación
> en segundos — con pérdida de datos mínima y sin tener que pagar
> el rescate."

---

## Preparación (antes de que llegue el público)

### 1. Verifica el entorno
```bash
# En la VM de base de datos (como root)
cd /opt/flight-booking-database/scripts   # o donde tengas los scripts
./pre_demo_check.sh
```
Todos los checks deben estar en verde. Si hay warnings, resuélvelos antes.

### 2. Abre las pantallas que vas a mostrar
- **Pantalla 1**: Observability Console → pestaña **Reservas** (gráfica timeline en vivo)
- **Pantalla 2**: Observability Console → pestaña **Systems** (estado de los 3 componentes)
- **Pantalla 3**: Observability Console → pestaña **Zerto** (VPGs, RPO en tiempo real)
- **Pantalla 4** (opcional): Frontend de negocio (login.html) con el panel del RBG visible

### 3. Confirma que el RBG está generando
En la Observability Console, el KPI "Última reserva hace" debe mostrar < 10s.
Si el RBG no está activo, ábrelo desde el frontend y verifica que arranca.

---

## Flujo de la demo (10-15 minutos)

### ACTO 1 — Estado normal (2-3 min)

**Muestra la pestaña Reservas:**
> "Llevamos generando reservas de forma continua. Podéis ver el
> timeline con la actividad de las últimas 24 horas, los ingresos
> acumulados y el KPI de última reserva — en este momento, hace
> solo unos segundos."

**Muestra la pestaña Systems:**
> "Los tres componentes están verdes: Frontend, Backend y Base de
> datos. Todo operativo."

**Muestra la pestaña Zerto:**
> "Y aquí vemos la protección de datos en tiempo real: el VPG está
> en estado MeetingSLA, con un RPO actual de pocos segundos. Zerto
> está replicando continuamente cada cambio en la base de datos
> hacia el site de recuperación."

---

### ACTO 2 — Pre-ataque: insertar checkpoint (1 min)

**En la VM de base de datos:**
```bash
source /opt/flight-booking-backend/scripts/.env
./zerto_insert-checkpoint.sh "ResilienceApp Production" "Pre-ransomware demo $(date '+%H:%M')"
```

**Mientras se ejecuta:**
> "Antes de simular el ataque, insertamos un checkpoint manual en
> Zerto — un marcador de tiempo limpio que podemos usar como punto
> de recuperación. En un escenario real, esto equivaldría a tener
> un punto de consistencia conocido justo antes del incidente."

Muestra en la pestaña Zerto que el checkpoint aparece en los eventos recientes.

---

### ACTO 3 — El ataque (2-3 min)

**En la VM de base de datos:**
```bash
cd /path/to/scripts
./encrypt_postgres.sh
```

**Mientras el script corre, muestra la Observability Console en tiempo real:**

El script tardará ~1-2 minutos (backup + cifrado + padding). Durante ese tiempo:

1. **~15s después**: el backend pierde la conexión con la BD → Systems muestra Backend en rojo
2. **~30s después**: el KPI "Última reserva hace" empieza a subir en amarillo/rojo
3. **Al terminar el padding**: el gráfico de disco en Systems muestra el aumento
4. **Timeline**: la gráfica de reservas por minuto cae a cero

**Mientras el público ve el impacto:**
> "El ataque ha cifrado los ficheros de la base de datos y ha
> detenido el servicio. La Observability Console lo refleja
> inmediatamente: el Backend ya no puede conectar a PostgreSQL,
> las reservas han parado, y el disco se está llenando con los
> ficheros cifrados del ransomware."
>
> "En un escenario real, este sería el momento de pánico: la
> operación está parada, los datos cifrados, y el atacante pide
> un rescate. Nosotros tenemos Zerto."

---

### ACTO 4 — Recuperación con Zerto (3-5 min)

**Muestra la pestaña Zerto de la Observability Console:**
> "El VPG sigue replicado en el site DR. Vamos a hacer el failover."

**Ejecuta el failover desde la consola de Zerto** (UI del ZVMA o desde la pestaña Zerto):
1. Selecciona el VPG → Failover Test o Live Failover
2. Selecciona el checkpoint que insertamos antes como punto de recuperación
3. Confirma

**Mientras se ejecuta:**
> "Zerto está recuperando las VMs en el site DR usando el punto
> de consistencia que marcamos antes del ataque. El RPO — la
> cantidad de datos que podríamos perder — es de solo los segundos
> entre el checkpoint y el inicio del ataque."

**Cuando el failover termina:**
- El backend del site DR arranca
- La Observability Console vuelve a verde
- El KPI "Última reserva hace" vuelve a actualizarse
- La gráfica de timeline muestra el gap del ataque y la recuperación

> "Recuperado. El sistema está operativo de nuevo en el site DR,
> con pérdida de datos prácticamente nula. Este es el valor de
> Zerto frente a un ransomware: no pagas el rescate, no negocias,
> simplemente vuelves atrás en el tiempo."

---

### ACTO 5 — Reset del entorno (post-demo, en privado)

Una vez terminada la demo, para dejar el entorno listo para la siguiente:

```bash
# En la VM de base de datos
./restore_postgres.sh
```

Esto:
1. Para PostgreSQL
2. Elimina los ficheros cifrados
3. Restaura desde el backup local que hizo el script de ataque
4. Arranca PostgreSQL y el backend
5. Limpia el backup (opcional)

---

## Preguntas frecuentes durante la demo

**¿Cuánto tiempo tardó la recuperación?**
> "El failover de Zerto tarda en función del tamaño de las VMs
> y la conectividad entre sites. En esta demo, típicamente entre
> 1 y 5 minutos. En producción con RPO configurado a segundos,
> la pérdida de datos es mínima."

**¿Y los datos que se generaron durante el ataque?**
> "Desde el checkpoint hasta el inicio del ataque, todos los datos
> están replicados. Lo que ocurrió durante el cifrado en sí —
> esos pocos segundos— es el RPO real. Que en este caso son las
> reservas generadas durante el tiempo que tardó el script en
> ejecutarse."

**¿Esto funciona contra cualquier ransomware?**
> "Zerto no previene el ransomware, lo combate. La clave es que
> replica continuamente a un site separado que el ransomware no
> puede alcanzar. El atacante cifra el site de producción, pero
> el site DR permanece intacto."

---

## IPs de referencia

| VM | IP | Servicio |
|---|---|---|
| Frontend | 10.10.44.13 | nginx :80 |
| Backend | 10.10.44.14 | FastAPI :8000 |
| Base de datos | 10.10.44.X | PostgreSQL :5432 |
| Observability | 10.10.44.16 | nginx :80 |
| ZVMA Origen | 10.10.44.12 | Zerto API :443 |
| ZVMA Destino | 10.10.44.32 | Zerto API :443 |

*(Ajusta las IPs según tu entorno real)*
