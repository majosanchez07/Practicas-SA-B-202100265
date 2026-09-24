#!/usr/bin/env bash
# ==============================================================================
# Prueba de restauracion de datos con medicion del RPO real
#
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
#
#  1. Marca A "antes-del-respaldo" en la base.
#  2. Respaldo de Velero a partir del schedule (misma plantilla, con el hook
#     de pg_dump).
#  3. Marca B "despues-del-respaldo": ESTA se va a perder, a proposito. Es la
#     forma honesta de medir el RPO: lo escrito despues del ultimo respaldo.
#  4. Desastre de datos: se borran las filas y se elimina el volumen.
#  5. Restauracion del volumen desde el respaldo.
#  6. Verificacion del CONTENIDO (no del tamano): marca A presente, marca B
#     ausente, conteo de filas y ultima fila del cronjob.
# ==============================================================================
source "$(dirname "$0")/comun.sh"

mkdir -p "$EVID/restauracion"
REG="$EVID/restauracion/prueba-datos-$(date -u +%Y%m%dT%H%M%SZ).log"
STS=sa-platform-postgresql
PVC=data-sa-platform-postgresql-0

log "$REG" "=== PRUEBA DE RESTAURACION DE DATOS ==="
psql_app "CREATE SCHEMA IF NOT EXISTS dr; CREATE TABLE IF NOT EXISTS dr.verificacion (id serial PRIMARY KEY, nota text NOT NULL, creado timestamptz NOT NULL DEFAULT now());" >/dev/null
psql_app "INSERT INTO dr.verificacion (nota) VALUES ('antes-del-respaldo-$(date -u +%H%M%S)')" >/dev/null
log "$REG" "1. Marca A insertada. Contenido de dr.verificacion:"
psql_app "SELECT id, nota, creado FROM dr.verificacion ORDER BY id" | tee -a "$REG"
N_ANTES=$(psql_app "SELECT count(*) FROM cronjobs.ejecuciones")
log "$REG" "1. Filas en cronjobs.ejecuciones = $N_ANTES; ultima = $(psql_app 'SELECT max(ejecutado_en) FROM cronjobs.ejecuciones')"

BK="prueba-datos-$(date -u +%Y%m%d%H%M%S)"
log "$REG" "2. Respaldo $BK (desde el schedule $SCHEDULE)"
velero backup create "$BK" --from-schedule "$SCHEDULE" --wait | tee -a "$REG"
T_RESPALDO=$(velero backup get "$BK" -o json | jq -r '.status.startTimestamp')
log "$REG" "2. Fase = $(velero backup get "$BK" -o json | jq -r .status.phase); inicio = $T_RESPALDO; snapshots = $(velero backup get "$BK" -o json | jq -r '.status.volumeSnapshotsCompleted // 0')"
log "$REG" "2. Volcado del hook dentro del volumen: $(kubectl -n "$NS_APP" exec $STS-0 -c postgresql -- bash -c 'ls -l /bitnami/postgresql/respaldo/ | tail -n +2 | tr "\n" " "; cat /bitnami/postgresql/respaldo/marca.txt')"

sleep 5
psql_app "INSERT INTO dr.verificacion (nota) VALUES ('despues-del-respaldo-$(date -u +%H%M%S)')" >/dev/null
log "$REG" "3. Marca B insertada DESPUES del respaldo (se espera perderla)"

# --- Desastre de datos ---------------------------------------------------------
T_DESASTRE=$(ahora)
log "$REG" "4. DESASTRE: DELETE de todas las filas y eliminacion del volumen"
psql_app "DELETE FROM dr.verificacion; DELETE FROM cronjobs.ejecuciones;" >/dev/null
log "$REG" "4. Filas tras el borrado: dr.verificacion=$(psql_app 'SELECT count(*) FROM dr.verificacion'), cronjobs.ejecuciones=$(psql_app 'SELECT count(*) FROM cronjobs.ejecuciones')"
# ArgoCD revertiria el escalado a 0 (selfHeal): se pausa la sincronizacion
# automatica de la raiz y de sa-platform durante la restauracion.
for a in "$APP_RAIZ" sa-platform; do
  kubectl -n argocd patch application "$a" --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null
done
kubectl -n "$NS_APP" scale statefulset $STS --replicas=0
kubectl -n "$NS_APP" wait --for=delete pod/$STS-0 --timeout=180s || true
kubectl -n "$NS_APP" delete pvc $PVC --wait=true
log "$REG" "4. Volumen $PVC eliminado"

# --- Restauracion --------------------------------------------------------------
T_R0=$(epoch)
RS="restaura-$BK"
velero restore create "$RS" --from-backup "$BK" --include-namespaces "$NS_APP" \
  --include-resources persistentvolumeclaims,persistentvolumes \
  --restore-volumes=true --wait | tee -a "$REG"
log "$REG" "5. Restauracion $RS fase = $(velero restore get "$RS" -o json | jq -r .status.phase)"
kubectl -n "$NS_APP" scale statefulset $STS --replicas=1
kubectl -n "$NS_APP" wait --for=condition=Ready pod/$STS-0 --timeout=600s
T_R1=$(epoch)
for a in "$APP_RAIZ"; do
  kubectl -n argocd patch application "$a" --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null
done
log "$REG" "5. Base de datos en linea. Tiempo de restauracion de datos = $((T_R1-T_R0)) s (la raiz reactiva la sincronizacion de sa-platform)"

# --- Verificacion del contenido -------------------------------------------------
log "$REG" "6. VERIFICACION DEL CONTENIDO RESTAURADO - dr.verificacion:"
psql_app "SELECT id, nota, creado FROM dr.verificacion ORDER BY id" | tee -a "$REG"
N_DESPUES=$(psql_app "SELECT count(*) FROM cronjobs.ejecuciones")
log "$REG" "6. cronjobs.ejecuciones: antes del respaldo=$N_ANTES, restauradas=$N_DESPUES; ultima restaurada = $(psql_app 'SELECT max(ejecutado_en) FROM cronjobs.ejecuciones')"
A=$(psql_app "SELECT count(*) FROM dr.verificacion WHERE nota LIKE 'antes-%'")
B=$(psql_app "SELECT count(*) FROM dr.verificacion WHERE nota LIKE 'despues-%'")
[ "$A" -ge 1 ] && log "$REG" "6. OK: la marca A (anterior al respaldo) fue recuperada" || log "$REG" "6. FALLO: marca A no recuperada"
[ "$B" -eq 0 ] && log "$REG" "6. Marca B perdida, como se esperaba: fue escrita despues del respaldo"

S_RESPALDO=$(date -u -d "$T_RESPALDO" +%s); S_DESASTRE=$(date -u -d "$T_DESASTRE" +%s)
log "$REG" "RPO REAL = desastre ($T_DESASTRE) - inicio del respaldo ($T_RESPALDO) = $((S_DESASTRE-S_RESPALDO)) s"
log "$REG" "Datos no recuperados: todo lo escrito despues de $T_RESPALDO (marca B y las ejecuciones del cronjob posteriores)."
echo "Registro: $REG"
