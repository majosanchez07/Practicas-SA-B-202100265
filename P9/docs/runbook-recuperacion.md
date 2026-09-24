# Runbook de recuperación ante desastres

Práctica 9 · María José Tebalán Sánchez · 202100265

Este procedimiento lo puede seguir una persona que no conoce el sistema y que no
puede contactar a la autora. Cada paso trae el comando exacto y la verificación
que debe cumplirse **antes** de pasar al siguiente. Si una verificación falla,
consulte la sección [Si algo falla](#si-algo-falla).

---

## 0. Cuándo usar este runbook

| Síntoma | Escenario | Sección |
|---|---|---|
| El clúster `aks-sa-p9-202100265` no existe, o no responde y no se puede recuperar | Pérdida total | [2](#2-reconstrucción-completa-pérdida-total) |
| El clúster funciona, pero se borraron o corrompieron los datos de PostgreSQL | Pérdida de datos | [3](#3-restauración-de-datos-sin-perder-el-clúster) |
| Un nodo va a entrar en mantenimiento o se perdió | Pérdida de nodo | [4](#4-pérdida-o-mantenimiento-de-un-nodo) |

**Roles durante el incidente** (clase del 17/09: "nadie opera solo en una crisis"):

- **Decide:** quien declara el incidente y elige el escenario de la tabla.
- **Ejecuta:** quien corre los comandos de este runbook.
- **Comunica:** quien informa el avance con las marcas de tiempo que imprimen los scripts.

Con un solo operador disponible, esa persona cubre los tres roles, pero anota
las decisiones en el registro.

---

## 1. Prerrequisitos (5 minutos)

### 1.1 Herramientas

```bash
for h in git az terraform kubectl helm velero jq openssl; do
  command -v $h >/dev/null && echo "OK  $h" || echo "FALTA $h"
done
```
✅ Todas deben decir `OK`. Versiones probadas: Terraform 1.9.8, Velero CLI 1.18.2,
kubectl 1.31.

### 1.2 Código

```bash
git clone https://github.com/majosanchez07/Practicas-SA-B-202100265.git
cd Practicas-SA-B-202100265
```

### 1.3 Sesión de Azure (suscripción de la práctica, región `centralus`)

```bash
az login
az account set --subscription "Azure subscription 1"
az account show --query "{suscripcion:name, usuario:user.name}"
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)   # lo usa Terraform
```
✅ Debe mostrar la suscripción de la práctica. No se necesita ninguna otra
credencial: las de Kubernetes, Velero y Sealed Secrets se derivan de esta
sesión. Velero usa workload identity y la llave está en Key Vault.

> La suscripción es compartida con el proyecto (grupos `rg-bankusac-*`, en
> `eastus`/`eastus2`). **No toque esos grupos.** La práctica 9 vive solo en
> `rg-sa-p9-*`, en `centralus`.

### 1.4 Lo que tiene que sobrevivir fuera del clúster

```bash
az group show -n rg-sa-p9-base-202100265 --query properties.provisioningState
az storage blob list --account-name sap9tfstate202100265 -c tfstate --auth-mode login --query "[].name"
az storage account show -n sap9velero202100265 --query provisioningState
az storage blob list --account-name sap9velero202100265 -c velero --auth-mode login --prefix backups/ --query "[].name" -o tsv | cut -d/ -f2 | sort -u | tail -3
az keyvault secret show --vault-name kv-sa-p9-202100265 -n sealed-secrets-key --query name
```
✅ Los cinco comandos deben responder sin error, y el cuarto debe listar al menos
un respaldo. Los snapshots de disco están en el mismo grupo:
`az snapshot list -g rg-sa-p9-base-202100265 -o table`.
❌ Si falta el **grupo base** o el **estado**, ejecute `./P9/scripts/crear-backend.sh`.
Terraform no encontrará un estado previo y creará todo desde cero, que es lo
correcto porque el clúster ya no existe.
❌ Si falta la **llave** (`kv-sa-p9-202100265/sealed-secrets-key`), los SealedSecret del
repositorio no se pueden descifrar. Vaya a [Si algo falla → llave perdida](#llave-de-sealed-secrets-perdida).
❌ Si no hay **respaldos**, la plataforma se reconstruye, pero con la base de
datos vacía. Registre esa pérdida en el informe.

---

## 2. Reconstrucción completa (pérdida total)

Anote la hora de inicio: el RTO se mide desde la destrucción hasta el paso 2.3.

### 2.1 Ejecutar el punto de entrada único

```bash
./P9/scripts/bootstrap.sh
```

El script hace, en orden y sin pedir nada:

| Paso | Qué hace | Lo que se ve si va bien |
|---|---|---|
| 0 | Comprueba el backend, el bucket y la llave | `PASO 0 OK` |
| 1 | `terraform apply` en `P9/terraform/cluster`: grupo, AKS, 2 nodos, identidad de Velero (6–10 min) | `PASO 1 OK: ... 2 nodos` |
| 2 | `terraform apply` en `P9/terraform/platform`, sin la app raíz: namespaces, cuotas, RBAC, StorageClass, llave de Sealed Secrets, Sealed Secrets, Velero, ArgoCD | `PASO 2 OK` |
| 3 | `velero restore` de los PVC del último respaldo completado | `PASO 3 OK: volúmenes restaurados (2 PVC)` |
| 4 | `terraform apply` con la app raíz `raiz-sa-p9` | `PASO 4 OK` |
| 5 | Espera a que cada Application quede Synced/Healthy | 7 líneas `PASO 5: ... Synced/Healthy` |
| 6 | Verifica secretos, datos, políticas y schedule | líneas `VERIFICACION:` |

El registro con marcas de tiempo queda en
`P9/docs/evidencias/reconstruccion/registro-<fecha>.log`.

**Por qué el paso 3 va antes que el 4:** si ArgoCD creara primero PostgreSQL,
nacería un volumen vacío con el mismo nombre, y Velero no sobrescribe un
volumen que ya existe. Con este orden, ArgoCD encuentra el volumen restaurado y
lo adopta.

### 2.2 Si el script se interrumpe

Vuelva a ejecutarlo. Todos los pasos son idempotentes: Terraform solo crea lo
que falta, y el paso 3 salta los volúmenes que ya existen. Si un `terraform apply`
se queda bloqueado con `Error acquiring the state lock`, otra persona está
aplicando en ese momento. Confirme que nadie más está operando y ejecute:

```bash
terraform -chdir=P9/terraform/<cluster|platform> force-unlock <LOCK_ID>
```

### 2.3 Verificación final

```bash
kubectl -n argocd get applications
```
✅ Las 7 aplicaciones aparecen `Synced` y `Healthy`: `raiz-sa-p9`, `argo-rollouts`,
`kyverno`, `politicas-admision`, `secretos-cifrados`, `respaldos-velero`,
`sa-platform`.

```bash
kubectl -n sa-p8 get secret sa-platform-secret            # secretos descifrados
kubectl -n sa-p8 get pods                                 # todo Running
kubectl -n sa-p8 exec sa-platform-postgresql-0 -c postgresql -- \
  bash -c 'PGPASSWORD=$POSTGRES_PASSWORD psql -h 127.0.0.1 -U biblioteca -d biblioteca \
  -c "select count(*), max(ejecutado_en) from cronjobs.ejecuciones"'   # datos reales, no vacío
kubectl get clusterpolicy                                 # 3 políticas de admisión
kubectl -n velero get schedule respaldo-sa-p9             # los respaldos siguen programados
kubectl argo rollouts get rollout sa-platform-api-gateway -n sa-p8   # entrega progresiva viva
```
✅ `max(ejecutado_en)` debe ser cercana a la hora del último respaldo. La
diferencia con la hora del desastre es el **RPO real**.

```bash
kubectl port-forward svc/sa-platform-api-gateway -n sa-p8 18080:8080 &
curl -s localhost:18080/health/ready
```
✅ Debe devolver HTTP 200.

---

## 3. Restauración de datos (sin perder el clúster)

```bash
./P9/scripts/prueba-restauracion-datos.sh
```

Si el problema es real y no una prueba, haga lo mismo que el script, pero a mano
y a partir del respaldo **anterior** al daño:

```bash
velero backup get                                  # elija el último Completed ANTERIOR al daño
B=<nombre-del-respaldo>
# 1. Pausar la sincronización automática (si no, ArgoCD revierte el escalado)
kubectl -n argocd patch application raiz-sa-p9  --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl -n argocd patch application sa-platform --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
# 2. Detener la base y retirar el volumen dañado
kubectl -n sa-p8 scale statefulset sa-platform-postgresql --replicas=0
kubectl -n sa-p8 delete pvc data-sa-platform-postgresql-0
# 3. Restaurar el volumen desde el snapshot
velero restore create --from-backup $B --include-namespaces sa-p8 \
  --include-resources persistentvolumeclaims,persistentvolumes --wait
# 4. Levantar la base y reactivar la sincronización automática
kubectl -n sa-p8 scale statefulset sa-platform-postgresql --replicas=1
kubectl -n argocd patch application raiz-sa-p9 --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```
✅ `velero restore get` muestra `Completed`, y la consulta del paso 2.3 devuelve
filas.

**Si el volumen restaurado arranca con errores de PostgreSQL** (por ejemplo, un
snapshot tomado a mitad de una escritura), el volcado consistente está en el mismo
volumen:

```bash
kubectl -n sa-p8 exec sa-platform-postgresql-0 -c postgresql -- bash -c \
 'cat /bitnami/postgresql/respaldo/marca.txt; PGPASSWORD=$POSTGRES_PASSWORD psql -h 127.0.0.1 -U biblioteca -d biblioteca -f /bitnami/postgresql/respaldo/biblioteca.sql'
```

---

## 4. Pérdida o mantenimiento de un nodo

```bash
kubectl get nodes
kubectl drain <nodo> --ignore-daemonsets --delete-emptydir-data --timeout=600s
# ... mantenimiento ...
kubectl uncordon <nodo>
```
✅ Durante el drenaje el servicio sigue respondiendo. Los PodDisruptionBudget
hacen que `drain` espere a que existan reemplazos. La prueba automatizada es
`./P9/scripts/prueba-perdida-nodo.sh`.
❌ Si `drain` se queda en `Cannot evict pod as it would violate the pod's
disruption budget` por más de 5 minutos, el otro nodo no tiene capacidad
suficiente. Agregue un nodo:

```bash
terraform -chdir=P9/terraform/cluster apply -var nodos=3   # ojo: la cuota de centralus es de 4 vCPU
```

Si el nodo se **perdió** (no fue drenado), el conjunto de escalado de AKS lo
reemplaza solo. PostgreSQL y RabbitMQ tienen una sola réplica, así que quedan fuera de
servicio hasta que su disco administrado se vuelva a montar en otro nodo (unos minutos,
mientras Azure lo desasocia del nodo perdido). Esto está documentado como punto único de fallo en el informe.

---

## Si algo falla

### Llave de Sealed Secrets perdida
No hay forma de descifrar los SealedSecret que están en el repositorio. Hay que
rotar todas las credenciales:

1. Deje que el controlador genere una llave nueva y respáldela con
   `./P9/scripts/respaldar-llave-sealed.sh`.
2. Vuelva a crear y cifrar las credenciales, siguiendo `P8/docs/despliegue.md`
   §4.2, y publique el nuevo `platform/sealed-secrets/credenciales.yaml` en el
   repositorio GitOps.
3. Cambie la contraseña de PostgreSQL restaurada para que coincida:
   `ALTER USER biblioteca PASSWORD '...'`.

### Velero no ve los respaldos (`velero backup get` vacío)
```bash
kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}'
```
Debe decir `Available`. Si dice `Unavailable`, revise que el ServiceAccount
`velero-server` tenga la anotación `azure.workload.identity/client-id`, que el pod
lleve la etiqueta `azure.workload.identity/use=true` y que exista la identidad
`id-velero-sa-p9` con su credencial federada (las crea la capa `cluster`). Velero sincroniza el
catálogo cada minuto: espere 60 segundos y repita.

### Una Application queda `OutOfSync` o `Degraded`
```bash
kubectl -n argocd get application <app> -o jsonpath='{.status.conditions}'
```
Con `kyverno`, el primer intento puede fallar por el tamaño de los CRD. Ya tiene
`ServerSideApply=true` y reintenta solo durante 10 intentos. Con `sa-platform`
en `Degraded`, casi siempre es `ImagePullBackOff`. Revise que exista el Secret
`ghcr-credenciales` en `sa-p8`: sale del SealedSecret
`platform/sealed-secrets/ghcr-credenciales.yaml`. Si el token de GitHub expiró,
vuelva a cifrarlo sin acceso al clúster:
```bash
kubectl create secret docker-registry ghcr-credenciales -n sa-p8 --docker-server=ghcr.io \
  --docker-username=majosanchez07 --docker-password="$(gh auth token)" --dry-run=client -o yaml \
  | kubeseal --cert P9/docs/sealed-secrets-cert.pem --format yaml \
  > ../Practicas-SA-B-202100265-gitops/platform/sealed-secrets/ghcr-credenciales.yaml
```

### `terraform destroy` del clúster se queda bloqueado
Revise si queda algún recurso en el grupo del clúster o en el de nodos:
```bash
az resource list -g rg-sa-p9-202100265 -o table
az resource list -g rg-sa-p9-nodos-202100265 -o table
```
Como último recurso, borre el grupo y repita el `destroy`:
`az group delete -n rg-sa-p9-202100265 --yes`. Nunca borre
`rg-sa-p9-base-202100265`: ahí están el estado, los respaldos y la llave.
