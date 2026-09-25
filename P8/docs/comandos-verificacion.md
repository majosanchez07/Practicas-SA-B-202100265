# Comandos de verificación

Práctica 8 — María José Tebalán Sánchez — 202100265

Estos son los comandos que se usaron para recoger cada evidencia. Cualquiera de
ellos puede volver a ejecutarse contra el entorno para comprobar el estado por
cuenta propia.

**Datos de la entrega:**

| Dato | Valor |
|---|---|
| Aplicación | `sa-platform` |
| Espacio de trabajo de la aplicación | `sa-p8` |
| Espacio del operador | `argocd` |
| Carga con entrega progresiva | `sa-platform-api-gateway` |
| Artefacto firmado | `ghcr.io/majosanchez07/practicas-sa-b-202100265/p8-api-gateway:1.0.1` |

---

## 0. Conectarse al entorno

```bash
cd P8/terraform/cluster
eval "$(terraform output -raw comando_kubeconfig)"
kubectl get nodes -o wide
```

Resultado obtenido: dos nodos en estado `Ready`, versión 1.31, región
`us-east-2`.

---

## 1. Infraestructura como código (8 pts)

### Que el código existe y es válido

```bash
cd P8/terraform/cluster  && terraform init -backend=false && terraform validate
cd ../platform           && terraform init -backend=false && terraform validate
```

### Que la infraestructura NO se creó a mano

```bash
kubectl get namespaces -l gestionado-por=terraform
```

Devuelve los cuatro espacios de trabajo. Esa etiqueta la pone la declaración de
infraestructura: un recurso creado con un comando suelto no la llevaría.

### Cuotas, límites y permisos

```bash
kubectl describe resourcequota -n sa-p8
kubectl describe limitrange    -n sa-p8
kubectl get roles,rolebindings -n sa-p8
kubectl get storageclass
```

**Evidencia:** [evidencias/terraform/](evidencias/terraform/) ·
capturas [01](evidencias/capturas/01-nodos-cluster.png),
[02](evidencias/capturas/02-terraform-namespaces-cuotas.png),
[03](evidencias/capturas/03-terraform-rbac.png)

---

## 2. Empaquetado (8 pts)

```bash
cd P8/charts/sa-platform
helm dependency build .

helm lint . -f values.example.yaml -f values-dev.yaml  --set namespace.name=sa-p8
helm lint . -f values.example.yaml -f values-prod.yaml --set namespace.name=sa-p8
```

### Que la validación está dentro de la automatización

```bash
grep -n "helm lint" .github/workflows/p8-gitops.yml
```

### Que ninguna referencia usa una etiqueta móvil

```bash
helm template sa-platform P8/charts/sa-platform \
  -f P8/charts/sa-platform/values.example.yaml \
  -f P8/charts/sa-platform/values-prod.yaml \
  --set namespace.name=sa-p8 \
  --set postgresql.enabled=false --set rabbitmq.enabled=false \
  | grep -E 'image:.*:latest' || echo "ninguna referencia móvil"
```

---

## 3. Modelo declarativo (14 pts)

### Estado de la aplicación

```bash
kubectl get application sa-platform -n argocd -o wide
```

Resultado obtenido: `Synced` y `Healthy`.

### Detalle, incluido el repositorio de origen

```bash
kubectl get application sa-platform -n argocd \
  -o jsonpath='{.status.sync.status} / {.status.health.status} — {.spec.sources[0].repoURL}{"\n"}'
```

### Historial de sincronizaciones

```bash
kubectl get application sa-platform -n argocd \
  -o jsonpath='{range .status.history[*]}revisión {.id}: {.deployedAt}{"\n"}{end}'
```

### Que la automatización no puede desplegar

```bash
./P8/scripts/verificar-sin-despliegue-directo.sh
```

Comprueba catorce patrones distintos de despliegue directo y de uso de
credenciales del entorno. Se ejecuta además como primera etapa de la
automatización, antes de construir nada.

Para comprobar que el control funciona de verdad, se ejecutó también contra la
automatización de la práctica anterior —que sí desplegaba— y la detecta:

```bash
./P8/scripts/verificar-sin-despliegue-directo.sh \
  .github/workflows-p7-archivado/p7-cicd.yml
```

### Interfaz gráfica

```bash
kubectl port-forward svc/argocd-server -n argocd 8081:80
# Abrir http://localhost:8081  (http, no https: la instalación usa modo inseguro)

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

**Evidencia:** capturas [04](evidencias/capturas/04-argocd-synced-healthy.png),
[16](evidencias/capturas/16-argocd-interfaz-y-pipeline.png),
[17](evidencias/capturas/17-argocd-arbol-recursos.png),
[18](evidencias/capturas/18-argocd-historial.png)

---

## 4. Entrega progresiva y reversión (14 pts)

### Estado y estrategia

```bash
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8
```

### Que la promoción avanza por etapas

```bash
kubectl get rollout sa-platform-api-gateway -n sa-p8 \
  -o jsonpath='{.spec.strategy.canary.steps}' | python3 -m json.tool
```

Tres etapas de promoción con reparto de tráfico —20%, 50% y 80%—, más la
promoción final al 100%. El enunciado exige al menos tres.

### Que cada etapa está condicionada al análisis

```bash
kubectl get analysistemplates -n sa-p8
kubectl get rollout sa-platform-api-gateway -n sa-p8 \
  -o jsonpath='{.spec.strategy.canary.analysis}' | python3 -m json.tool
```

### Evidencia de la reversión

```bash
kubectl get analysisruns -n sa-p8
kubectl get analysisruns -n sa-p8 \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.status.phase}{"\n"}{end}'
```

Detalle del análisis que falló:

```bash
AR=$(kubectl get analysisruns -n sa-p8 --sort-by=.metadata.creationTimestamp \
     -o name | tail -1)
kubectl get "$AR" -n sa-p8 \
  -o jsonpath='{range .status.metricResults[*]}{.name}: {.phase} (éxitos: {.successful}, fallos: {.failed}){"\n"}{end}'
```

Resultado obtenido durante el incidente:

| Prueba | Resultado |
|---|---|
| Disponibilidad | Superada — el componente estaba vivo |
| Rendimiento | Superada — respondía dentro de los umbrales |
| **Funcionalidad** | **Fallida** — el servicio esencial devolvía error |

Mensaje del controlador:

```
RolloutAborted: Rollout aborted update to revision 4:
Metric "prueba-integracion" assessed Failed due to failed (1) > failureLimit (0)
```

**Recuperación en 66 segundos, con un 20% del tráfico afectado durante 24
segundos, sin intervención humana.**

**Evidencia:** [evidencias/rollouts/](evidencias/rollouts/) ·
capturas [06](evidencias/capturas/06-rollout-promocion.png),
[07](evidencias/capturas/07-reversion-cronologia.png),
[08](evidencias/capturas/08-reversion-analisis.png)

---

## 5. Validación automatizada (8 pts)

### Abrir un canal hacia el componente expuesto

```bash
kubectl port-forward svc/sa-platform-api-gateway -n sa-p8 18080:8080
```

### Las tres suites

```bash
cd P8/tests
BASE_URL=http://localhost:18080 ./humo.sh          # 6 de 6
BASE_URL=http://localhost:18080 ./integracion.sh   # 9 de 9
k6 run -e BASE_URL=http://localhost:18080 -e VUS=5 -e DURACION=30s k6-carga.js
```

Resultado de la prueba de rendimiento: 612 peticiones, 0% de error, percentil 95
de 122 ms frente al umbral de 500 ms. Veredicto: promover.

### Que el análisis ejecuta pruebas reales, no comprobaciones triviales

```bash
kubectl get analysistemplates -n sa-p8 -o json \
  | python3 -c "import json,sys; [print(' ', m['name'], '->', list(m['provider'].keys())) for t in json.load(sys.stdin)['items'] for m in t['spec']['metrics']]"
```

Cada métrica usa un proveedor de tipo `job`: lanza un contenedor que ejecuta las
pruebas contra la versión candidata.

**Evidencia:** [evidencias/pruebas/](evidencias/pruebas/),
[evidencias/carga/](evidencias/carga/) ·
capturas [11](evidencias/capturas/11-pruebas-humo.png),
[12](evidencias/capturas/12-prueba-carga.png)

---

## 6. Cadena de suministro y políticas (8 pts)

### Políticas activas y en modo de rechazo

```bash
kubectl get clusterpolicies
kubectl get clusterpolicy prohibir-etiqueta-latest \
  -o jsonpath='{.spec.validationFailureAction}{"\n"}'
```

Las tres aparecen como `Ready`, en modo `Enforce`: rechazan, no solo informan.

### Demostración del rechazo

```bash
kubectl apply -f P8/policies/pruebas/pod-que-viola-las-politicas.yaml
kubectl get pod pod-violador -n sa-p8   # debe responder "not found"
```

El manifiesto incumple las tres normas a propósito y el objeto no llega a
crearse.

### Sin necesidad de entorno, con la herramienta de línea de comandos

```bash
cd P8/policies
kyverno apply 01-prohibir-latest.yaml 02-exigir-limites.yaml 03-exigir-sin-root.yaml \
  --resource pruebas/pod-que-viola-las-politicas.yaml
```

### Análisis de vulnerabilidades con capacidad de bloqueo

```bash
grep -n -A 8 "Analisis de vulnerabilidades" .github/workflows/p8-gitops.yml
```

Lo que convierte el análisis en un control y no en un informe es `exit-code: 1`
con `severity: CRITICAL`: sin esa bandera imprimiría las vulnerabilidades y la
construcción seguiría.

### Firma del artefacto

```bash
cosign verify \
  ghcr.io/majosanchez07/practicas-sa-b-202100265/p8-api-gateway:1.0.1 \
  --certificate-identity-regexp "^https://github.com/majosanchez07/Practicas-SA-B-202100265/.*$" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

La verificación exige que el firmante sea el flujo de trabajo de este
repositorio. Sin `--certificate-identity-regexp` se aceptaría cualquier firma
válida, incluida la de un tercero.

### Credenciales cifradas

```bash
kubectl get sealedsecrets -n sa-p8

grep -E "JWT_SECRET|PASSWORD" \
  ../Practicas-SA-B-202100265-gitops/platform/sealed-secrets/credenciales.yaml
```

Solo devuelve valores cifrados, nunca credenciales legibles.

**Evidencia:** [evidencias/politicas/](evidencias/politicas/),
[evidencias/seguridad/](evidencias/seguridad/) ·
capturas [09](evidencias/capturas/09-politicas-activas.png),
[10](evidencias/capturas/10-rechazo-politica.png),
[13](evidencias/capturas/13-firma-verificada.png),
[15](evidencias/capturas/15-secretos-cifrados.png)

---

## 7. Separación de repositorios

```bash
git log --oneline -5
git -C ../Practicas-SA-B-202100265-gitops log --oneline -5
```

Dos repositorios independientes: el de código y el de declaración. La
automatización solo puede escribir en el segundo, y únicamente mediante una
propuesta de cambio.

**Evidencia:** captura [14](evidencias/capturas/14-flujo-git.png)

---

## Resumen de una sola pasada

Para comprobar el estado completo de un vistazo:

```bash
kubectl get nodes
kubectl get application sa-platform -n argocd -o wide
kubectl get namespaces -l gestionado-por=terraform
kubectl get clusterpolicies
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8
kubectl get pods -n sa-p8
```

Estado registrado al cerrar la recolección de evidencias:

| Comprobación | Resultado |
|---|---|
| Nodos | 2 operativos |
| Aplicación | **Synced / Healthy** |
| Espacios declarados | 4 |
| Políticas activas | 3 |
| Promoción por etapas | 6 de 6, estado sano |
| Cargas de trabajo | 11 operativas |
