#!/usr/bin/env bash
# ==============================================================================
# Pruebas de humo — Practica 8
# Maria Jose Tebalan Sanchez — 202100265
#
# Que es una prueba de humo
# -------------------------
# El nombre viene del hardware: al encender una placa nueva por primera vez, lo
# primero que se comprueba es que no salga humo. Aqui es lo mismo: la
# comprobacion mas barata y rapida de que el despliegue no esta roto de raiz.
# No valida logica de negocio; valida que el servicio arranco y responde.
#
# Cuando se ejecuta
# -----------------
#   1. Manualmente, tras un despliegue, para confirmar que el sistema vive.
#   2. Dentro del AnalysisTemplate del canary, en cada paso de la promocion.
#      Ahi la ejecuta un Job con la misma logica que este script.
#
# Los dos endpoints y por que son distintos
# -----------------------------------------
#   /health/live   ¿el proceso esta vivo? NO consulta la base de datos a
#                  proposito: si lo hiciera, una caida temporal de Postgres
#                  reiniciaria todos los pods, lo que no arregla la base y
#                  ademas agrega un CrashLoopBackOff al incidente.
#
#   /health/ready  ¿puede atender trafico? SI verifica las dependencias. Un pod
#                  que falla aqui sale del balanceo pero sigue vivo, y vuelve
#                  solo cuando la dependencia se restablece.
#
# Uso:
#   ./humo.sh                                   # contra localhost:8080
#   BASE_URL=http://mi-gateway:8080 ./humo.sh
#   ./humo.sh --json                            # salida para el reporte
# ==============================================================================
set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
TIMEOUT="${TIMEOUT:-5}"
FORMATO="texto"
[ "${1:-}" = "--json" ] && FORMATO="json"

TOTAL=0
FALLOS=0
RESULTADOS=()

# ------------------------------------------------------------------------------
# Ejecuta una comprobacion y acumula el resultado.
#   $1 descripcion legible
#   $2 ruta
#   $3 codigo HTTP esperado
# ------------------------------------------------------------------------------
comprobar() {
  local descripcion="$1" ruta="$2" esperado="$3"
  local codigo tiempo inicio fin

  TOTAL=$((TOTAL + 1))
  inicio=$(date +%s%N)
  codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time "${TIMEOUT}" "${BASE_URL}${ruta}" 2>/dev/null || echo 000)
  fin=$(date +%s%N)
  tiempo=$(( (fin - inicio) / 1000000 ))

  if [ "${codigo}" = "${esperado}" ]; then
    [ "${FORMATO}" = "texto" ] && printf "  OK     %-38s %s  (%s ms)\n" "${descripcion}" "${codigo}" "${tiempo}"
    RESULTADOS+=("{\"prueba\":\"${descripcion}\",\"ruta\":\"${ruta}\",\"esperado\":${esperado},\"obtenido\":${codigo},\"ms\":${tiempo},\"resultado\":\"paso\"}")
  else
    [ "${FORMATO}" = "texto" ] && printf "  FALLA  %-38s %s  (se esperaba %s)\n" "${descripcion}" "${codigo}" "${esperado}"
    RESULTADOS+=("{\"prueba\":\"${descripcion}\",\"ruta\":\"${ruta}\",\"esperado\":${esperado},\"obtenido\":${codigo},\"ms\":${tiempo},\"resultado\":\"fallo\"}")
    FALLOS=$((FALLOS + 1))
  fi
}

if [ "${FORMATO}" = "texto" ]; then
  echo "==============================================================="
  echo "  PRUEBAS DE HUMO — Practica 8 — 202100265"
  echo "  Destino: ${BASE_URL}"
  echo "==============================================================="
  echo ""
fi

# ------------------------------------------------------------------------------
# El gateway: es la unica puerta de entrada y el servicio con canary.
# ------------------------------------------------------------------------------
comprobar "gateway vivo"                 "/health/live"   200
comprobar "gateway listo"                "/health/ready"  200

# ------------------------------------------------------------------------------
# Los microservicios, a traves del gateway. No se golpea ninguno directamente:
# el enunciado de la P5 establecio que la unica entrada es el Ingress, y esa
# decision se mantiene.
# ------------------------------------------------------------------------------
comprobar "auth accesible via gateway"   "/auth/health/live"           200
comprobar "books accesible via gateway"  "/books/health/live"          200
comprobar "loans accesible via gateway"  "/loans/health/live"          200
comprobar "notifications via gateway"    "/notifications/health/live"  200

if [ "${FORMATO}" = "json" ]; then
  printf '{"suite":"humo","total":%d,"fallos":%d,"fecha":"%s","pruebas":[%s]}\n' \
    "${TOTAL}" "${FALLOS}" "$(date -Iseconds)" \
    "$(IFS=,; echo "${RESULTADOS[*]}")"
else
  echo ""
  echo "---------------------------------------------------------------"
  printf "  %d de %d comprobaciones superadas\n" "$((TOTAL - FALLOS))" "${TOTAL}"
  echo "---------------------------------------------------------------"
fi

# Codigo de salida distinto de cero: es lo que hace fallar el Job del analisis
# y, con el, aborta la promocion del canary.
[ "${FALLOS}" -eq 0 ] || exit 1
