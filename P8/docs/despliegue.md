# Guía de despliegue

Práctica 8 — María José Tebalán Sánchez — 202100265

Procedimiento completo, desde una cuenta vacía hasta el sistema funcionando con
las cuatro demostraciones capturadas.

---

## Antes de empezar

### Herramientas necesarias

```bash
for h in terraform kubectl helm argocd kyverno kubeseal cosign trivy k6 aws gh \
         kubectl-argo-rollouts; do
  printf "%-24s %s\n" "$h" "$(command -v $h || echo FALTA)"
done
```

### Credenciales

```bash
aws sts get-caller-identity     # debe devolver la cuenta
gh auth status                  # debe indicar sesión activa
```

### Advertencia sobre el costo

El entorno cuesta aproximadamente 0.26 dólares por hora, unos 6.20 al día. El
reloj empieza a correr con el primer `terraform apply` de la capa de entorno.

**No es necesario mantenerlo encendido entre el desarrollo y la evaluación.** El
procedimiento completo, desde la creación hasta la captura de las cuatro
evidencias, toma entre noventa minutos y dos horas.

---

## Fase 1 — Entorno de ejecución

Entre quince y veinte minutos; el plano de control es lo más lento.

```bash
cd P8/terraform/cluster
terraform init
terraform plan -out=plan.tfplan | tee ../../docs/evidencias/terraform/plan-cluster.txt
terraform apply plan.tfplan     | tee ../../docs/evidencias/terraform/apply-cluster.txt
```

Configurar el acceso y comprobar:

```bash
eval "$(terraform output -raw comando_kubeconfig)"
kubectl get nodes -o wide
```

Deben aparecer dos nodos en estado `Ready`.

---

## Fase 2 — Espacios de trabajo, cuotas, límites y permisos

```bash
cd ../platform
terraform init
terraform plan -out=plan.tfplan | tee ../../docs/evidencias/terraform/plan-platform.txt
terraform apply plan.tfplan     | tee ../../docs/evidencias/terraform/apply-platform.txt
```

Evidencia de que la infraestructura no se creó a mano:

```bash
kubectl get namespaces -l gestionado-por=terraform \
  | tee ../../docs/evidencias/terraform/namespaces.txt
kubectl describe resourcequota -n sa-p8 \
  | tee ../../docs/evidencias/terraform/cuotas.txt
kubectl get roles,rolebindings -n sa-p8 \
  | tee ../../docs/evidencias/terraform/rbac.txt
```

---

## Fase 3 — Componentes internos

Los cuatro componentes que viven dentro del entorno. Se instalan una sola vez.

### 3.1 Motor de declaración

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd --namespace argocd --version 7.7.5 \
  --set configs.params."server\.insecure"=true
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
```

Obtener la credencial inicial y acceder:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 3.2 Controlador de promoción

```bash
helm install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts --create-namespace --version 2.38.0
kubectl rollout status deployment/argo-rollouts -n argo-rollouts --timeout=300s
```

### 3.3 Motor de admisión

```bash
helm repo add kyverno https://kyverno.github.io/kyverno
helm repo update
helm install kyverno kyverno/kyverno --namespace kyverno --version 3.3.4
kubectl rollout status deployment/kyverno-admission-controller -n kyverno --timeout=300s
```

### 3.4 Gestión de credenciales cifradas

```bash
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace sealed-secrets --version 2.20.0 \
  --set fullnameOverride=sealed-secrets-controller
kubectl rollout status deployment/sealed-secrets-controller -n sealed-secrets --timeout=300s
```

---

## Fase 4 — Credenciales

Ninguna credencial viaja en texto claro al repositorio de declaración.

### 4.1 Acceso al almacén de artefactos

Los artefactos publicados desde un repositorio privado nacen privados.

```bash
kubectl create secret docker-registry ghcr-credenciales \
  --docker-server=ghcr.io \
  --docker-username=majosanchez07 \
  --docker-password="$(gh auth token)" \
  --namespace sa-p8
```

### 4.2 Credenciales de la aplicación, cifradas

Se generan localmente, se cifran con la clave pública del controlador y solo
entonces se publican. El archivo en claro nunca sale de la máquina.

```bash
cd P8

# Generar valores aleatorios
JWT=$(openssl rand -hex 32)
AES=$(openssl rand -hex 16)
PGPASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
RMQPASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

# Construir el objeto en claro, SIN aplicarlo al entorno
kubectl create secret generic sa-platform-secretos \
  --namespace sa-p8 \
  --from-literal=JWT_SECRET_KEY="$JWT" \
  --from-literal=AES_SECRET_KEY="$AES" \
  --from-literal=POSTGRES_PASSWORD="$PGPASS" \
  --from-literal=RABBITMQ_PASSWORD="$RMQPASS" \
  --dry-run=client -o yaml > /tmp/secreto-en-claro.yaml

# Cifrar
kubeseal --controller-name sealed-secrets-controller \
         --controller-namespace sealed-secrets \
         --format yaml < /tmp/secreto-en-claro.yaml \
         > ../Practicas-SA-B-202100265-gitops/platform/sealed-secrets/credenciales.yaml

# Eliminar el archivo en claro
shred -u /tmp/secreto-en-claro.yaml
```

El archivo cifrado resultante puede publicarse en un repositorio público sin
riesgo: **solo el controlador que lo cifró puede descifrarlo**, usando una clave
privada que nunca sale del entorno.

Comprobar que no queda nada legible:

```bash
grep -E "JWT_SECRET|PASSWORD" \
  ../Practicas-SA-B-202100265-gitops/platform/sealed-secrets/credenciales.yaml \
  || echo "No hay credenciales legibles en el archivo publicado"
```

---

## Fase 5 — Normas de admisión

```bash
kubectl apply -f ../Practicas-SA-B-202100265-gitops/platform/kyverno/politicas.yaml
kubectl get clusterpolicies
```

Las tres deben aparecer como `Ready: True`.

---

## Fase 6 — Registrar la aplicación

```bash
kubectl apply -f ../Practicas-SA-B-202100265-gitops/apps/sa-platform.yaml
argocd app wait sa-platform --timeout 600
argocd app get sa-platform
```

**Requisito de evaluación:** debe mostrar `Sync Status: Synced` y
`Health Status: Healthy`.

Evidencia:

```bash
argocd app get sa-platform     | tee docs/evidencias/argocd/estado.txt
argocd app history sa-platform | tee docs/evidencias/argocd/historial.txt
kubectl get all -n sa-p8       | tee docs/evidencias/argocd/recursos.txt
```

---

## Fase 7 — Las cuatro demostraciones

### 7.1 Despliegue rechazado por norma

```bash
kubectl apply -f P8/policies/pruebas/pod-que-viola-las-politicas.yaml \
  2>&1 | tee P8/docs/evidencias/politicas/rechazo.txt
```

Resultado esperado: error de admisión enumerando las normas incumplidas. El
objeto **no** debe crearse.

### 7.2 Promoción exitosa

```bash
cd Practicas-SA-B-202100265
git tag v1.0.0 && git push origin v1.0.0
```

Observar la automatización, y al fusionar la propuesta de promoción:

```bash
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8 --watch
```

Debe avanzar por las cuatro etapas y terminar en `Healthy`.

### 7.3 Reversión automática

Introducir el defecto en el componente expuesto:

```bash
cd P8/services/api-gateway
# Modificar la ruta del catálogo para que devuelva un error del servidor.
git add -A && git commit -m "Version defectuosa para demostrar la contencion"
git tag v1.0.1 && git push origin main v1.0.1
```

Al fusionar la propuesta, observar y capturar:

```bash
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8 --watch \
  | tee ../../docs/evidencias/rollouts/reversion.txt
kubectl get analysisruns -n sa-p8
kubectl describe analysisrun <nombre> -n sa-p8 \
  | tee ../../docs/evidencias/rollouts/analisis-fallido.txt
```

Resultado esperado: el avance se detiene en la primera etapa, el análisis
registra el fallo y el tráfico vuelve íntegro a la versión estable.

**Anotar los tiempos** de cada transición: el informe de incidente los pide.

### 7.4 Bloqueo por vulnerabilidad crítica

En una rama aparte, sustituir la imagen base por una versión antigua con
vulnerabilidades conocidas, y abrir una propuesta de cambio:

```bash
git checkout -b demo/vulnerabilidad
# Modificar el Dockerfile con una imagen base antigua
git commit -am "Demostracion: imagen base con vulnerabilidad critica"
git push -u origin demo/vulnerabilidad
gh pr create --title "Demostracion de bloqueo por vulnerabilidad" \
             --body "Esta propuesta debe quedar bloqueada."
```

La verificación de seguridad debe fallar y bloquear la propuesta. Guardar la
URL.

---

## Fase 8 — Prueba de rendimiento

```bash
kubectl port-forward svc/sa-platform-api-gateway -n sa-p8 8080:8080 &
cd P8/tests
BASE_URL=http://localhost:8080 ./humo.sh        | tee ../docs/evidencias/pruebas/humo.txt
BASE_URL=http://localhost:8080 ./integracion.sh | tee ../docs/evidencias/pruebas/integracion.txt
k6 run -e BASE_URL=http://localhost:8080 k6-carga.js
mv reporte-carga.* ../docs/evidencias/carga/
```

---

## Fase 9 — Completar el README

Los campos marcados como pendientes deben rellenarse con las URL reales.

**Un enlace ausente o roto se califica con cero en su criterio, sin búsqueda
adicional en el repositorio.** Comprobar cada uno en una ventana privada del
navegador, sin sesión iniciada.

```bash
for u in <cada URL de la tabla>; do
  printf "%-70s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' "$u")"
done
```

---

## Fase 10 — Destruir el entorno

Tras capturar todas las evidencias:

```bash
cd P8/terraform/platform && terraform destroy
cd ../cluster            && terraform destroy
```

Comprobar que no queda nada facturable:

```bash
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=tag:Practica,Values=P8" \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId'
aws elbv2 describe-load-balancers --region us-east-2 \
  --query 'LoadBalancers[].LoadBalancerName'
```

Ambos deben devolver listas vacías.

---

## Recrear para la evaluación

El día de la evaluación el sistema debe estar sincronizado y sano. Recrearlo
toma unos cuarenta minutos:

1. Fases 1 y 2: infraestructura.
2. Fase 3: componentes internos.
3. Fase 4: credenciales.
4. Fases 5 y 6: normas y registro de la aplicación.

Las demostraciones ya están capturadas como evidencia y no hace falta
repetirlas.

**Conviene dejar margen**: iniciar la recreación al menos una hora antes de la
evaluación, no minutos antes.
