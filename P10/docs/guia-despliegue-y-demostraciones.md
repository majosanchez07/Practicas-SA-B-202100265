# Guía de despliegue y demostraciones

Práctica 10 · María José Tebalán Sánchez · 202100265

Parte del clúster de la Práctica 9 (AKS, `centralus`) con ArgoCD y la
aplicación raíz `raiz-sa-p9` operando. Nada de lo siguiente usa
`kubectl apply` ni `helm install`: todo entra por los dos repositorios.

## 1. Publicar las imágenes instrumentadas

```bash
git push origin main
git tag p10-v1.1.0 && git push origin p10-v1.1.0
```

El workflow `P10 - GitOps` ejecuta pruebas, `helm lint`, `promtool` (reglas y
pruebas de alertas), Kyverno, Trivy, SBOM y Cosign, publica
`ghcr.io/majosanchez07/practicas-sa-b-202100265/p10-*:1.1.0` y abre un Pull
Request en el repositorio GitOps con `imageTag: "1.1.0"`.

## 2. Activar el stack por GitOps

Los cambios del repositorio GitOps (stack de observabilidad y `sa-platform`
apuntando a `P10/charts/sa-platform`) se empujan **después** de que existan
las imágenes `p10-*`; si no, los pods quedarían en `ImagePullBackOff`.

```bash
cd Practicas-SA-B-202100265-gitops
git push origin main
```

La aplicación raíz crea en este orden (olas de sincronización):

| Ola | Aplicaciones |
|---|---|
| 1 | `observabilidad-monitoreo` (CRDs de Prometheus), `observabilidad-loki`, `observabilidad-tempo` |
| 2 | `observabilidad-collector`, `observabilidad-promtail`, `observabilidad-config` |
| 3 | `sa-platform` (PrometheusRule, tablero, generador de tráfico, AnalysisTemplate) |

Comprobación:

```bash
kubectl -n argocd get applications
kubectl -n observabilidad get pods
kubectl -n sa-p8 get prometheusrule,analysistemplate,rollout
```

## 3. Acceso a las interfaces

```bash
kubectl -n observabilidad port-forward svc/monitoreo-grafana 3000:80
kubectl -n observabilidad port-forward svc/monitoreo-prometheus 9090:9090
kubectl -n observabilidad port-forward svc/monitoreo-alertmanager 9093:9093
```

La credencial de Grafana (usuario `admin`) está en el SealedSecret
`grafana-admin`; para leerla:

```bash
kubectl -n observabilidad get secret grafana-admin -o jsonpath='{.data.clave}' | base64 -d
```

## 4. Requisitos para optar a la calificación

```bash
# Stack operativo: Prometheus recolecta las métricas de los servicios
curl -s 'http://127.0.0.1:9090/api/v1/query?query=sum by (service_name) (rate(sa_http_requests_total[5m]))' | jq '.data.result'

# Canary por métricas: el AnalysisTemplate usa el proveedor prometheus, no job
kubectl -n sa-p8 get analysistemplate sa-platform-api-gateway-analisis-metricas -o jsonpath='{.spec.metrics[*].provider}' | jq

# SLO calculándose
curl -s 'http://127.0.0.1:9090/api/v1/query?query=slo:presupuesto_consumido:ratio' | jq '.data.result'
```

## 5. Demostración A: reversión del canary por métricas

```bash
./P10/scripts/evidencia-reversion-canary.sh      # terminal 1, queda esperando
```

En el repositorio GitOps, `environments/prod/values.yaml`:

```yaml
services:
  api-gateway:
    fault:
      enabled: true        # antes: false
```

`git commit -am "Induce regresion de latencia en el canary" && git push`.

Qué se observa: el Rollout crea la revisión nueva al 20 %, a los ~60 s el
AnalysisRun mide la candidata, la tasa de error (~15 % en `/loans` y `/books`)
y el p95 (~0.9 s) superan los umbrales, y tras la segunda medición fallida el
Rollout se aborta y vuelve al 100 % a la estable. El script guarda el registro
con marcas de tiempo y el YAML del AnalysisRun en
`docs/evidencias/canary/`.

Para terminar: `fault.enabled: false`, commit y push. Como el Rollout quedó
abortado con la revisión defectuosa como deseada, al volver a la
configuración anterior ArgoCD la sincroniza y el Rollout vuelve a *Healthy*.

## 6. Demostración B: del síntoma a la causa

```bash
./P10/scripts/evidencia-sintoma-causa.sh          # terminal 1
```

En el repositorio GitOps:

```yaml
services:
  books-service:
    fault:
      enabled: true
```

El script registra el inicio del fallo, la primera señal (5xx en el gateway)
y el momento en que la alerta `SLODisponibilidadConsumoRapido` pasa a
*firing*. Después pide pulsar Enter en cada paso del recorrido:

1. **Alerta** (Alertmanager, `localhost:9093`): abrir la alerta; la anotación
   `runbook_url` lleva al runbook.
2. **Tablero** (*Biblioteca: operación*, fila Errores): solo `/books` falla
   en el gateway, y books-service muestra la misma curva.
3. **Traza** (Grafana → Explore → Tempo → Search, `service.name =
   api-gateway`, *status* error): el span de books-service está en error con
   ~400 ms y sin spans de base de datos.
4. **Registro** (botón *Logs for this span*): la línea JSON de
   books-service con `"message":"pool de conexiones agotado..."` y el mismo
   `trace_id`.

Por último, revertir (`fault.enabled: false`, push) y pulsar Enter: el script
mide el tiempo hasta el estado estable y hasta que la alerta se resuelve.

## 7. Captura y exportación del tablero

El JSON del tablero vive en `P10/charts/sa-platform/dashboards/operacion.json`
y llega a Grafana como ConfigMap. Si se modifica en la interfaz, se exporta
(*Share → Export → Save to file*) sobre ese mismo archivo y se publica por Pull
Request; de lo contrario ArgoCD restauraría la versión del repositorio.
