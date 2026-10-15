# Guía de grabación del video

Práctica 10 · María José Tebalán Sánchez · 202100265

Duración objetivo: **7 minutos** (la consigna pide de 5 a 8). Siete escenas.
Cada una dice qué preparar, qué mostrar en pantalla y qué decir. Los textos
entre comillas son una sugerencia: dilos con tus palabras.

---

## Antes de grabar (unos 40 minutos antes)

### 1. Comprobar que el clúster está sano

En Git Bash:

```bash
kubectl get nodes
kubectl -n argocd get applications
```

Las 13 aplicaciones deben estar en `Synced` / `Healthy`.

### 2. Encender el fallo de books-service 35 minutos antes

La alerta por consumo del presupuesto tarda unos 30 minutos en dispararse
(está medido y explicado en el informe). No se puede esperar en vivo, así que
se enciende antes y en el video se dice.

En el repositorio GitOps, `environments/prod/values.yaml`, bloque de
`books-service`:

```yaml
    fault:
      enabled: true        # antes: false
```

```bash
cd ~/Documents/SA/Practicas-SA-B-202100265-gitops
git commit -am "Induce agotamiento del pool en books-service (video)"
git push
```

Anota la hora del push: la dirás en la escena 6.

### 3. Abrir las interfaces (una terminal aparte, se queda abierta)

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
kubectl -n observabilidad port-forward svc/monitoreo-grafana 3000:80 &
kubectl -n observabilidad port-forward svc/monitoreo-alertmanager 9093:9093 &
```

Contraseñas:

```bash
# Grafana (usuario admin)
kubectl -n observabilidad get secret grafana-admin -o jsonpath='{.data.clave}' | base64 -d; echo
# ArgoCD (usuario admin)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Inicia sesión en las dos antes de grabar.

### 4. Dejar listas estas pestañas, en este orden

| # | Pestaña | Dirección |
|---|---|---|
| 1 | ArgoCD | https://localhost:8080 |
| 2 | Grafana, tablero | http://localhost:3000/d/sa-p10-operacion (rango: última hora) |
| 3 | Grafana, Explore con Tempo | http://localhost:3000/explore |
| 4 | Alertmanager | http://localhost:9093 |
| 5 | GitHub, P10/README.md | https://github.com/majosanchez07/Practicas-SA-B-202100265/tree/main/P10 |

Y una terminal de Git Bash con letra grande (Ctrl + rueda del ratón).

### 5. Cinco minutos antes, comprobar que la alerta ya disparó

En Alertmanager debe verse `SLODisponibilidadConsumoRapido`. Si no está,
espera: no empieces a grabar sin ella.

---

## Escena 1 · 0:00 a 0:45 · Qué se construyó y que todo entró por GitOps

**Pantalla:** pestaña de ArgoCD, la lista de aplicaciones.

**Mostrar:** las aplicaciones `observabilidad-monitoreo`, `-loki`, `-tempo`,
`-collector`, `-promtail`, `-config` y `sa-platform`, todas en verde.

**Decir:**
> "Esta es la Práctica 10. El sistema de las prácticas anteriores era una caja
> negra; ahora tiene trazas, métricas y registros correlacionados. Todo el
> stack, Prometheus, Grafana, Loki, Tempo y el Collector de OpenTelemetry, lo
> instala ArgoCD desde el repositorio GitOps; nada se instaló a mano."

---

## Escena 2 · 0:45 a 1:45 · Una petición, una sola traza

**Pantalla:** Grafana → Explore → origen de datos **Tempo** → pestaña
**Search**. En *Service Name* elige `loans-service` y pulsa *Run query*.
Abre una traza cuya raíz sea `api-gateway POST /loans`.

**Mostrar:** la cascada de spans: `api-gateway` → `loans-service`
(`graphql.resolve createLoan`, `SELECT`) → `books-service` (`POST /graphql`).

**Decir:**
> "Un préstamo atraviesa tres servicios. El contexto viaja en la cabecera
> traceparent, así que la petición completa es una sola traza: aquí se ve
> cuánto tardó cada servicio y cada consulta a la base."

---

## Escena 3 · 1:45 a 2:30 · De la traza a sus registros, y al revés

**Pantalla:** en la misma traza, clic en un span de `loans-service` →
botón **Logs for this span**.

**Mostrar:** se abre Loki con el registro JSON. Señala el campo `trace_id`.
Despliega el registro y haz clic en el enlace **Abrir traza en Tempo**:
vuelve a la misma traza.

**Decir:**
> "Los registros son JSON y llevan el trace_id. Desde la traza llego a sus
> registros, y desde el registro vuelvo a su traza. Además, Loki permite
> consultar por campo, por ejemplo solo los de nivel error."

---

## Escena 4 · 2:30 a 3:30 · El tablero de operación

**Pantalla:** pestaña del tablero. Recorre las filas de arriba abajo, sin
detenerte en cada panel.

**Mostrar y decir, fila por fila:**

| Fila | Qué decir |
|---|---|
| SLO | "Arriba, lo que le importa a alguien que no es ingeniero: si cumplimos lo prometido y cuánto presupuesto de error queda. Ahora está en rojo por el fallo que encendí hace 35 minutos." |
| Latencia | "Qué servicio hace esperar al usuario." |
| Tráfico | "Préstamos creados y rechazados por motivo: métricas de negocio. Se ven los rechazos por catálogo no disponible." |
| Errores | "Qué ruta falla y en qué servicio; aquí books-service tiene la misma curva que el gateway." |
| Saturación | "CPU, memoria y réplicas frente a sus límites." |

---

## Escena 5 · 3:30 a 5:00 · El canary decidido por métricas

**Pantalla:** terminal.

```bash
kubectl -n sa-p8 get analysistemplate sa-platform-api-gateway-analisis-metricas -o yaml | grep -A3 "provider:"
```

**Decir:**
> "El análisis del canary ya no ejecuta pruebas: consulta Prometheus. Mide la
> tasa de error y el p95 solo de la versión candidata, filtrando por su hash."

Luego muestra el AnalysisRun de la reversión real del 15/10:

```bash
kubectl -n sa-p8 get analysisrun sa-platform-api-gateway-5b97d8df46-3 \
  -o jsonpath='{range .status.metricResults[*]}{.name}: {.phase} -> {.measurements[*].value}{"\n"}{end}'
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8
```

**Decir:**
> "Induje una regresión en el gateway: 900 milisegundos más y un 15 % de
> errores, por GitOps. La candidata midió 10.7 y 12.1 % de error y un p95 de
> casi un segundo. Con dos mediciones fallidas, Argo Rollouts la revirtió solo,
> a los 2 minutos y medio, sin que nadie interviniera."

> **Opcional, si quieres mostrarlo en vivo** (suma unos 3 minutos que
> puedes acelerar al editar): pon `services.api-gateway.fault.enabled: true`
> en el repositorio GitOps, haz push y ejecuta
> `kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8 --watch`.
> Al terminar, vuelve a `false` y haz push.

---

## Escena 6 · 5:00 a 6:15 · Del síntoma a la causa, cronometrado

**Antes de empezar la escena:** pon en pantalla un cronómetro (el del
teléfono o https://www.online-stopwatch.com) y arráncalo al abrir la alerta.

**Pasos en pantalla:**

1. **Alertmanager:** abre `SLODisponibilidadConsumoRapido`, muestra la
   anotación `runbook_url` y ábrela. *"La alerta no es por un umbral: se
   dispara porque el presupuesto de error se consume 14 veces más rápido de lo
   sostenible. Trae su runbook."*
2. **Tablero, fila Errores:** *"Falla /books, y el servicio interno con la
   misma curva es books-service."*
3. **Explore → Tempo → Search:** Service Name `books-service`, Status
   `error`. Abre una traza. *"El span de books-service termina en 503 tras
   400 milisegundos, y no hay ninguna consulta a la base dentro."*
4. **Logs for this span:** *"Y aquí la causa: pool de conexiones agotado.
   El campo causa dice que es el fallo inducido."*
5. Detén el cronómetro. *"De la alerta al registro: X segundos."*

**Decir también:**
> "Encendí este fallo a las [hora del push]. La métrica lo mostró en
> segundos, pero la alerta tardó unos 30 minutos por su ventana de una hora;
> en el informe propongo una alerta de consumo muy rápido para acortarlo."

---

## Escena 7 · 6:15 a 7:00 · Recuperación y cierre

**Pantalla:** terminal, en el repositorio GitOps.

Vuelve a poner `enabled: false` en el bloque `fault` de `books-service`.

```bash
git commit -am "Corrige el pool de books-service (video)"
git push
```

Luego cambia a la pestaña de GitHub con el README de P10.

**Decir:**
> "La corrección también entra por GitOps; en la prueba medida, el error
> volvió por debajo del 0.5 % en 5 minutos. En el README están los tiempos
> medidos, la reversión en 2 minutos y medio y el recorrido alerta-registro en
> 3 segundos, y en el informe, lo que falló de mi propia instrumentación y cómo
> lo corregí."

---

## Después de grabar

1. Sube el video a Google Drive con acceso "Cualquier persona con el enlace".
   El enlace no debe pedir inicio de sesión.
2. En `P10/README.md` reemplaza los dos `⏱ PENDIENTE` del video por la URL, y
   ajusta los minutos de la tabla a los reales.
3. `git commit -am "P10: enlace y minutaje del video" && git push`
4. Confirma que el fallo quedó apagado:
   `kubectl -n argocd get application sa-platform` debe estar en `Synced` /
   `Healthy`.

## Si algo sale mal

| Problema | Solución |
|---|---|
| Grafana pide contraseña otra vez | Repite el comando de la contraseña del paso 3 |
| "Logs for this span" no muestra nada | Amplía el rango de tiempo de Explore a "Last 3 hours" |
| La alerta no aparece | Espera; el fallo tiene que llevar al menos 30 minutos activo |
| Un port-forward se cerró | Vuelve a ejecutar su línea del paso 3 |
| `kubectl` responde "Unauthorized" | `az aks get-credentials -g rg-sa-p9-202100265 -n aks-sa-p9-202100265 --overwrite-existing` |
