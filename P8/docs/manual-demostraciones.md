# Manual de las demostraciones

Práctica 8 — María José Tebalán Sánchez — 202100265

Este manual cubre las dos tareas que quedan: **preparar la versión defectuosa**
y **ejecutar el despliegue completo**. Están separadas porque la primera se hace
sin gastar nada y conviene tenerla lista antes de encender el entorno.

---

# PARTE A — Preparar la versión defectuosa

Tiempo: 15 minutos. Costo: ninguno.

## A.1 Qué defecto se introduce y por qué ése

El defecto debe cumplir una condición precisa: **ser invisible para las
comprobaciones de disponibilidad y visible solo al ejecutar la función real.**

Si se eligiera un defecto evidente —que el componente no arranque, por
ejemplo— las comprobaciones de arranque lo detendrían antes de que recibiera
tráfico. Eso no demostraría nada sobre el análisis progresivo, porque la
contención habría ocurrido antes.

El defecto elegido: **la ruta de acceso al catálogo devuelve un error del
servidor**. El componente arranca bien, responde a sus comprobaciones de estado,
se declara operativo y su instancia figura como disponible. Pero la función
principal del sistema no funciona para nadie.

Verificado previamente contra un simulador:

| Validación | Ante el defecto |
|---|---|
| Comprobación de vitalidad | Pasa |
| Comprobación de disponibilidad | Pasa |
| Prueba de disponibilidad del análisis | Pasa |
| **Prueba de funcionalidad del análisis** | **Falla** |

## A.2 Dónde está la ruta

El componente expuesto monta las rutas hacia los servicios internos en
`P8/services/api-gateway/src/index.js`:

```javascript
app.use('/auth',  crearProxy(AUTH_SERVICE_URL,  '/auth',  'Auth service'));
app.use('/books', crearProxy(BOOKS_SERVICE_URL, '/books', 'Books service'));
app.use('/loans', crearProxy(LOANS_SERVICE_URL, '/loans', 'Loans service'));
```

La ruta del catálogo es `/books`. El análisis la verifica a través de
`/books/health/live`, que es la ruta declarada en `criticalPaths`.

> Nota: durante la preparación de esta práctica esas rutas estaban declaradas
> como `/api/books`, que no existe en el código. De haberse dejado así, el
> análisis habría fallado siempre por un error de ruta no encontrada, y la
> reversión se habría disparado por el motivo equivocado. Conviene comprobar
> siempre que las rutas del análisis existan realmente en el código.

## A.3 Crear la rama y el cambio

```bash
cd ~/Documentos/SA/Practicas-SA-B-202100265
git checkout -b demo/version-defectuosa
```

Editar `P8/services/api-gateway/src/index.js` e insertar el bloque siguiente
**inmediatamente antes** de la línea que monta el proxy de `/books`:

```javascript
// ============================================================================
// DEFECTO INDUCIDO DELIBERADAMENTE — Practica 8
//
// Este bloque NO debe llegar a la rama principal. Existe para demostrar que el
// analisis progresivo detecta una version defectuosa y la revierte sin
// intervencion humana.
//
// Se eligio este defecto por una razon precisa: es invisible para las
// comprobaciones de disponibilidad. El componente arranca, responde a
// /health/live y /health/ready, y su instancia figura como disponible. Solo
// falla al ejecutar la funcion real.
//
// Un defecto evidente -que el proceso no arranque- seria detenido por las
// comprobaciones de arranque antes de recibir trafico, y no demostraria nada
// sobre el analisis progresivo.
// ============================================================================
app.use('/books', (req, res) => {
  res.status(500).json({
    error: 'Fallo inducido para la demostracion de reversion automatica',
    practica: 'P8',
    version: process.env.APP_VERSION || 'desconocida'
  });
});
```

El orden importa: este manejador debe declararse **antes** del proxy real, para
que intercepte las peticiones antes de que lleguen a él.

## A.4 Comprobar el defecto localmente

Antes de construir nada, conviene verificar que el defecto se comporta como se
espera.

```bash
cd P8/services/api-gateway
npm ci --no-audit --no-fund
PORT=8080 npm start &
```

En otra terminal:

```bash
cd ~/Documentos/SA/Practicas-SA-B-202100265/P8/tests

# Debe PASAR: el componente esta vivo
BASE_URL=http://localhost:8080 ./humo.sh
echo "humo -> $?"      # se espera 0

# Debe FALLAR: la funcion principal no responde
BASE_URL=http://localhost:8080 ./integracion.sh
echo "integracion -> $?"   # se espera 1
```

Ese contraste —humo pasa, funcionalidad falla— es exactamente lo que el informe
de incidente documenta. Conviene guardar la salida:

```bash
BASE_URL=http://localhost:8080 ./humo.sh \
  > ../docs/evidencias/pruebas/defecto-humo-pasa.txt 2>&1
BASE_URL=http://localhost:8080 ./integracion.sh \
  > ../docs/evidencias/pruebas/defecto-integracion-falla.txt 2>&1
```

Detener el proceso local antes de continuar.

## A.5 Publicar la rama, sin etiquetar todavía

```bash
cd ~/Documentos/SA/Practicas-SA-B-202100265
git add P8/services/api-gateway/src/index.js P8/docs/evidencias/
git commit -m "Version defectuosa para demostrar la reversion automatica

El acceso al catalogo devuelve un error del servidor. El componente sigue
arrancando y respondiendo a sus comprobaciones de estado, de modo que el
defecto solo es detectable ejecutando la funcion real.

Esta rama NO debe fusionarse en la principal."
git push -u origin demo/version-defectuosa
```

**No etiquetar todavía.** La etiqueta dispara la construcción y la propuesta de
promoción; eso se hace en la Parte B, cuando el entorno ya esté funcionando con
la versión correcta.

## A.6 Preparar también la demostración de bloqueo por vulnerabilidad

Segunda rama, independiente de la anterior.

```bash
git checkout main
git checkout -b demo/vulnerabilidad
```

Editar `P8/services/api-gateway/Dockerfile.prod` y sustituir la imagen base por
una versión antigua con vulnerabilidades conocidas. Por ejemplo, cambiar la
línea de la imagen base por:

```dockerfile
# IMAGEN BASE DELIBERADAMENTE ANTIGUA — demostracion de bloqueo
# Esta version tiene vulnerabilidades criticas conocidas. El analisis de
# seguridad debe detectarlas y bloquear la propuesta antes de que el artefacto
# llegue al almacen.
FROM node:16.14.0-alpine3.14 AS prod
```

Comprobar localmente que efectivamente tiene vulnerabilidades críticas:

```bash
trivy image --severity CRITICAL --ignore-unfixed node:16.14.0-alpine3.14
```

Si no aparece ninguna crítica, probar con una versión más antigua. La
demostración necesita al menos una.

```bash
git commit -am "Demostracion: imagen base con vulnerabilidad critica

Esta propuesta debe quedar bloqueada por el analisis de seguridad."
git push -u origin demo/vulnerabilidad
```

La propuesta de cambio se abre en la Parte B.

---

# PARTE B — Despliegue y captura de evidencias

Tiempo: entre 90 minutos y 2 horas. Costo: aproximadamente 0.26 dólares por
hora desde el primer paso.

## B.0 Antes de empezar

```bash
cd ~/Documentos/SA/Practicas-SA-B-202100265
git checkout main

# Herramientas
for h in terraform kubectl helm argocd kyverno kubeseal cosign trivy k6 aws gh \
         kubectl-argo-rollouts; do
  printf "%-24s %s\n" "$h" "$(command -v $h || echo FALTA)"
done

# Credenciales
aws sts get-caller-identity
gh auth status
```

Conviene tener el bloque de tiempo completo disponible: una vez creado el
entorno, dejarlo encendido sin usarlo solo acumula costo.

## B.1 Crear el entorno de ejecución

De quince a veinte minutos.

```bash
cd P8/terraform/cluster
terraform init
terraform plan -out=plan.tfplan | tee ../../docs/evidencias/terraform/plan-cluster.txt
```

Revisar el plan antes de aplicar. Debe crear alrededor de sesenta recursos y
ninguno destruido.

```bash
terraform apply plan.tfplan | tee ../../docs/evidencias/terraform/apply-cluster.txt
eval "$(terraform output -raw comando_kubeconfig)"
kubectl get nodes -o wide
```

Deben aparecer dos nodos en estado `Ready`.

## B.2 Espacios de trabajo, cuotas, límites y permisos

```bash
cd ../platform
terraform init
terraform plan -out=plan.tfplan | tee ../../docs/evidencias/terraform/plan-platform.txt
terraform apply plan.tfplan     | tee ../../docs/evidencias/terraform/apply-platform.txt
```

Evidencia de que nada se creó a mano:

```bash
kubectl get namespaces -l gestionado-por=terraform \
  | tee ../../docs/evidencias/terraform/namespaces.txt
kubectl describe resourcequota -n sa-p8 | tee ../../docs/evidencias/terraform/cuotas.txt
kubectl describe limitrange    -n sa-p8 | tee ../../docs/evidencias/terraform/limites.txt
kubectl get roles,rolebindings -n sa-p8 | tee ../../docs/evidencias/terraform/rbac.txt
```

## B.3 Componentes internos

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add kyverno https://kyverno.github.io/kyverno
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm repo update

# Motor de declaracion
helm install argocd argo/argo-cd --namespace argocd --version 7.7.5 \
  --set configs.params."server\.insecure"=true
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

# Controlador de promocion
helm install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts --create-namespace --version 2.38.0
kubectl rollout status deployment/argo-rollouts -n argo-rollouts --timeout=300s

# Motor de admision
helm install kyverno kyverno/kyverno --namespace kyverno --version 3.3.4
kubectl rollout status deployment/kyverno-admission-controller -n kyverno --timeout=300s

# Controlador de secretos cifrados
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace sealed-secrets --version 2.20.0 \
  --set fullnameOverride=sealed-secrets-controller
kubectl rollout status deployment/sealed-secrets-controller -n sealed-secrets --timeout=300s
```

Acceso a la interfaz del motor de declaración:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

Abrir `https://localhost:8080`, usuario `admin`.

## B.4 Credenciales

### Acceso al almacén de artefactos

```bash
kubectl create secret docker-registry ghcr-credenciales \
  --docker-server=ghcr.io \
  --docker-username=majosanchez07 \
  --docker-password="$(gh auth token)" \
  --namespace sa-p8
```

### Credenciales de la aplicación, cifradas

Ninguna credencial viaja en texto claro al repositorio.

```bash
cd ~/Documentos/SA/Practicas-SA-B-202100265

JWT=$(openssl rand -hex 32)
AES=$(openssl rand -hex 16)
PGPASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
RMQPASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

# Objeto en claro, generado en memoria y NO aplicado al entorno
kubectl create secret generic sa-platform-secretos \
  --namespace sa-p8 \
  --from-literal=JWT_SECRET_KEY="$JWT" \
  --from-literal=AES_SECRET_KEY="$AES" \
  --from-literal=POSTGRES_PASSWORD="$PGPASS" \
  --from-literal=RABBITMQ_PASSWORD="$RMQPASS" \
  --dry-run=client -o yaml > /tmp/en-claro.yaml

# Cifrar con la clave publica del controlador
mkdir -p ../Practicas-SA-B-202100265-gitops/platform/sealed-secrets
kubeseal --controller-name sealed-secrets-controller \
         --controller-namespace sealed-secrets \
         --format yaml < /tmp/en-claro.yaml \
         > ../Practicas-SA-B-202100265-gitops/platform/sealed-secrets/credenciales.yaml

# Destruir el archivo en claro
shred -u /tmp/en-claro.yaml
```

Comprobar que no queda nada legible antes de publicar:

```bash
grep -E "JWT_SECRET|PASSWORD" \
  ../Practicas-SA-B-202100265-gitops/platform/sealed-secrets/credenciales.yaml \
  && echo "ATENCION: hay algo legible, no publicar" \
  || echo "Correcto: no hay credenciales legibles"
```

Aplicar y publicar:

```bash
kubectl apply -f ../Practicas-SA-B-202100265-gitops/platform/sealed-secrets/credenciales.yaml
kubectl get secret sa-platform-secretos -n sa-p8

cd ../Practicas-SA-B-202100265-gitops
git add platform/sealed-secrets/
git commit -m "Agrega las credenciales cifradas de la aplicacion

Cifradas con la clave publica del controlador del entorno. Solo ese controlador
puede descifrarlas, con una clave privada que nunca sale del entorno."
git push
cd ../Practicas-SA-B-202100265
```

## B.5 Normas de admisión

```bash
kubectl apply -f ../Practicas-SA-B-202100265-gitops/platform/kyverno/politicas.yaml
kubectl get clusterpolicies
```

Las tres deben aparecer con `READY: True`.

## B.6 Registrar la aplicación

```bash
kubectl apply -f ../Practicas-SA-B-202100265-gitops/apps/sa-platform.yaml
argocd app wait sa-platform --timeout 600
argocd app get sa-platform
```

**Requisito de evaluación:** debe mostrar `Sync Status: Synced` y
`Health Status: Healthy`.

```bash
argocd app get sa-platform     | tee P8/docs/evidencias/argocd/estado.txt
argocd app history sa-platform | tee P8/docs/evidencias/argocd/historial.txt
kubectl get all -n sa-p8       | tee P8/docs/evidencias/argocd/recursos.txt
```

Capturar también la interfaz gráfica mostrando la aplicación sincronizada y
sana, en `P8/docs/evidencias/capturas/`.

---

## B.7 Demostración 1: despliegue rechazado por norma

La más rápida, y no requiere esperar nada.

```bash
kubectl apply -f P8/policies/pruebas/pod-que-viola-las-politicas.yaml \
  2>&1 | tee P8/docs/evidencias/politicas/rechazo.txt
```

Resultado esperado: error de admisión enumerando las normas incumplidas. El
objeto **no** debe crearse. Comprobarlo:

```bash
kubectl get pod pod-violador -n sa-p8 2>&1 | tee -a P8/docs/evidencias/politicas/rechazo.txt
```

Debe indicar que no se encontró.

## B.8 Demostración 2: bloqueo por vulnerabilidad crítica

```bash
gh pr create --base main --head demo/vulnerabilidad \
  --title "Demostracion: bloqueo por vulnerabilidad critica" \
  --body "Esta propuesta usa una imagen base con vulnerabilidades criticas conocidas y debe quedar bloqueada por el analisis de seguridad."
```

Esperar a que la automatización termine y comprobar que falló:

```bash
gh pr checks --watch
gh pr view --json url -q .url    # guardar esta URL para el README
```

Guardar una captura de la propuesta bloqueada.

**Importante:** no fusionar esta propuesta. Se deja abierta como evidencia.

## B.9 Demostración 3: promoción exitosa

```bash
git checkout main
git tag v1.0.0
git push origin v1.0.0
```

Seguir la ejecución:

```bash
gh run watch
```

Al terminar, la automatización abre una propuesta en el repositorio de
declaración. Revisarla y fusionarla:

```bash
gh pr list --repo majosanchez07/Practicas-SA-B-202100265-gitops
gh pr merge <numero> --repo majosanchez07/Practicas-SA-B-202100265-gitops --squash
```

Observar la promoción por etapas:

```bash
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8 --watch \
  | tee P8/docs/evidencias/rollouts/promocion-exitosa.txt
```

Debe avanzar por las cuatro etapas (20, 50, 80, 100 por ciento) y terminar en
`Healthy`. Son unos cuatro minutos.

Guardar además la URL de la ejecución para el README:

```bash
gh run list --limit 1 --json url -q '.[0].url'
```

## B.10 Demostración 4: reversión automática

La más importante de las cuatro: vale catorce puntos.

```bash
git checkout demo/version-defectuosa
git merge main --no-edit          # incorporar lo que haya cambiado
git push
git tag v1.0.1
git push origin v1.0.1
```

Esperar a que la automatización construya y abra la propuesta.

**Antes de fusionar**, preparar la observación en otra terminal, porque la
reversión ocurre en menos de dos minutos y conviene no perdérsela:

```bash
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8 --watch \
  | tee P8/docs/evidencias/rollouts/reversion.txt
```

Fusionar la propuesta y **anotar la hora exacta**: el informe de incidente pide
los tiempos.

```bash
date -Iseconds    # momento de la fusion
gh pr merge <numero> --repo majosanchez07/Practicas-SA-B-202100265-gitops --squash
```

Secuencia esperada:

1. El motor de declaración detecta el cambio y sincroniza.
2. El controlador inicia la promoción: 20 por ciento a la versión candidata.
3. El análisis ejecuta las pruebas contra la versión candidata.
4. La prueba de funcionalidad falla.
5. El avance se detiene y el tráfico vuelve íntegro a la versión estable.

Capturar la evidencia del análisis fallido:

```bash
kubectl get analysisruns -n sa-p8
kubectl describe analysisrun <nombre> -n sa-p8 \
  | tee P8/docs/evidencias/rollouts/analisis-fallido.txt
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8 \
  | tee P8/docs/evidencias/rollouts/estado-tras-reversion.txt
date -Iseconds    # momento de la recuperacion
```

Con las dos horas anotadas se completa la tabla de tiempos del informe de
incidente.

## B.11 Prueba de rendimiento

```bash
kubectl port-forward svc/sa-platform-api-gateway -n sa-p8 8080:8080 &
cd P8/tests
BASE_URL=http://localhost:8080 ./humo.sh        | tee ../docs/evidencias/pruebas/humo.txt
BASE_URL=http://localhost:8080 ./integracion.sh | tee ../docs/evidencias/pruebas/integracion.txt
k6 run -e BASE_URL=http://localhost:8080 k6-carga.js
mv reporte-carga.* ../docs/evidencias/carga/
cd ../..
```

## B.12 Evidencia de la cadena de suministro

```bash
mkdir -p P8/docs/evidencias/seguridad
gh run download --name "sbom-api-gateway-1.0.0"  --dir P8/docs/evidencias/seguridad/
gh run download --name "trivy-api-gateway-1.0.0" --dir P8/docs/evidencias/seguridad/

# Verificar la firma de forma independiente
cosign verify \
  ghcr.io/majosanchez07/practicas-sa-b-202100265/p8-api-gateway:1.0.0 \
  --certificate-identity-regexp "^https://github.com/majosanchez07/Practicas-SA-B-202100265/.*$" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  | tee P8/docs/evidencias/seguridad/verificacion-firma.txt
```

## B.13 Completar el README

Rellenar en `P8/README.md` cada campo marcado como pendiente con la URL real
recogida en los pasos anteriores.

**Un enlace ausente o roto se califica con cero en su criterio, sin búsqueda
adicional.** Comprobar cada uno sin sesión iniciada:

```bash
for u in <cada URL de la tabla>; do
  printf "%-70s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' "$u")"
done
```

Todos deben devolver 200.

## B.14 Destruir el entorno

Solo después de comprobar que todas las evidencias están guardadas.

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

# Recrear para la evaluación

El día de la evaluación el sistema debe estar sincronizado y sano. Recrearlo
toma unos cuarenta minutos: pasos B.1 a B.6. Las demostraciones ya están
capturadas y no hace falta repetirlas.

**Iniciar la recreación al menos una hora antes de la evaluación**, no minutos
antes.

---

# Resumen de tiempos

| Paso | Duración | Costo acumulado |
|---|---|---|
| Parte A completa | 15 min | 0 |
| B.1 Entorno de ejecución | 20 min | 0.09 |
| B.2 a B.6 Configuración | 25 min | 0.20 |
| B.7 a B.10 Demostraciones | 40 min | 0.37 |
| B.11 a B.13 Evidencias | 20 min | 0.46 |
| B.14 Destrucción | 10 min | 0.50 |

Costo total aproximado de una sesión completa: medio dólar. Recrear para la
evaluación añade unos 0.20 más.
