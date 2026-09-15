#!/usr/bin/env bash
# ==============================================================================
# Pruebas de integracion — Practica 8
# Maria Jose Tebalan Sanchez — 202100265
#
# En que se diferencian de las de humo
# ------------------------------------
# Las de humo preguntan "¿esta vivo?". Estas preguntan "¿hace lo que debe?".
#
# La distincion importa porque un servicio puede estar perfectamente sano y aun
# asi devolver 500 en su ruta principal: sus probes pasan, el pod figura como
# Ready, el Deployment aparece disponible, y sin embargo ningun usuario puede
# usarlo. Ese es exactamente el defecto que se induce deliberadamente para
# demostrar la reversion automatica, y es la razon de que el analisis del
# canary no se conforme con la prueba de humo.
#
# Que se prueba aqui
# ------------------
#   1. Los endpoints criticos responden 200.
#   2. Devuelven JSON valido (un 200 con cuerpo vacio o con una pagina de error
#      HTML no es una respuesta correcta).
#   3. El enrutamiento del gateway funciona: una peticion a /books llega
#      efectivamente a books-service y no a otro sitio.
#   4. Las rutas inexistentes devuelven 404 y no 500. Un 500 ante una ruta
#      desconocida delata que el error no se esta manejando.
#
# Uso:
#   ./integracion.sh
#   BASE_URL=http://mi-gateway:8080 ./integracion.sh
#   ./integracion.sh --json
# ==============================================================================
set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
TIMEOUT="${TIMEOUT:-10}"
FORMATO="texto"
[ "${1:-}" = "--json" ] && FORMATO="json"

TOTAL=0
FALLOS=0
RESULTADOS=()

registrar() {
  local descripcion="$1" resultado="$2" detalle="$3"
  TOTAL=$((TOTAL + 1))
  if [ "${resultado}" = "paso" ]; then
    [ "${FORMATO}" = "texto" ] && printf "  OK     %-44s %s\n" "${descripcion}" "${detalle}"
  else
    [ "${FORMATO}" = "texto" ] && printf "  FALLA  %-44s %s\n" "${descripcion}" "${detalle}"
    FALLOS=$((FALLOS + 1))
  fi
  RESULTADOS+=("{\"prueba\":\"${descripcion}\",\"resultado\":\"${resultado}\",\"detalle\":\"${detalle}\"}")
}

# ------------------------------------------------------------------------------
# Comprueba codigo HTTP.
# ------------------------------------------------------------------------------
probar_codigo() {
  local descripcion="$1" ruta="$2" esperado="$3" codigo
  codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time "${TIMEOUT}" "${BASE_URL}${ruta}" 2>/dev/null || echo 000)
  if [ "${codigo}" = "${esperado}" ]; then
    registrar "${descripcion}" "paso" "HTTP ${codigo}"
  else
    registrar "${descripcion}" "fallo" "HTTP ${codigo}, se esperaba ${esperado}"
  fi
}

# ------------------------------------------------------------------------------
# Comprueba codigo HTTP Y que el cuerpo sea JSON valido.
#
# Un 200 con el cuerpo vacio, o con una pagina de error de un proxy, no es una
# respuesta correcta aunque el codigo lo sugiera.
# ------------------------------------------------------------------------------
probar_json() {
  local descripcion="$1" ruta="$2" cuerpo codigo respuesta
  respuesta=$(curl -s -w '\n%{http_code}' --max-time "${TIMEOUT}" "${BASE_URL}${ruta}" 2>/dev/null || echo -e "\n000")
  codigo=$(echo "${respuesta}" | tail -1)
  cuerpo=$(echo "${respuesta}" | sed '$d')

  if [ "${codigo}" != "200" ]; then
    registrar "${descripcion}" "fallo" "HTTP ${codigo}"
    return
  fi
  if [ -z "${cuerpo}" ]; then
    registrar "${descripcion}" "fallo" "HTTP 200 con cuerpo vacio"
    return
  fi
  if echo "${cuerpo}" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    registrar "${descripcion}" "paso" "HTTP 200, JSON valido"
  else
    registrar "${descripcion}" "fallo" "HTTP 200 pero el cuerpo no es JSON"
  fi
}

if [ "${FORMATO}" = "texto" ]; then
  echo "==============================================================="
  echo "  PRUEBAS DE INTEGRACION — Practica 8 — 202100265"
  echo "  Destino: ${BASE_URL}"
  echo "==============================================================="
  echo ""
  echo "-- Endpoints criticos --"
fi

# ------------------------------------------------------------------------------
# 1. Endpoints criticos del negocio.
#
# Son los que el AnalysisTemplate verifica en cada paso del canary
# (criticalPaths en los values) y los que el fallo inducido rompe.
# ------------------------------------------------------------------------------
probar_json   "catalogo de libros"              "/api/books"
probar_codigo "gateway vivo"                    "/health/live"   200
probar_codigo "gateway listo"                   "/health/ready"  200

[ "${FORMATO}" = "texto" ] && { echo ""; echo "-- Enrutamiento del gateway --"; }

# ------------------------------------------------------------------------------
# 2. El gateway enruta hacia cada microservicio.
#
# Verifica que el proxy inverso funciona, no solo que el gateway responde.
# ------------------------------------------------------------------------------
probar_codigo "ruta hacia auth-service"          "/auth/health/live"           200
probar_codigo "ruta hacia books-service"         "/books/health/live"          200
probar_codigo "ruta hacia loans-service"         "/loans/health/live"          200
probar_codigo "ruta hacia notifications-service" "/notifications/health/live"  200

[ "${FORMATO}" = "texto" ] && { echo ""; echo "-- Manejo de errores --"; }

# ------------------------------------------------------------------------------
# 3. Las rutas inexistentes devuelven 404, no 500.
#
# Un 500 ante una ruta desconocida significa que una excepcion no controlada
# esta escapando hasta el manejador de errores. Es un sintoma de que el codigo
# no valida sus entradas.
# ------------------------------------------------------------------------------
probar_codigo "ruta inexistente devuelve 404"    "/api/esta-ruta-no-existe"    404
probar_codigo "recurso inexistente devuelve 404" "/api/books/999999999"        404

if [ "${FORMATO}" = "json" ]; then
  printf '{"suite":"integracion","total":%d,"fallos":%d,"fecha":"%s","pruebas":[%s]}\n' \
    "${TOTAL}" "${FALLOS}" "$(date -Iseconds)" \
    "$(IFS=,; echo "${RESULTADOS[*]}")"
else
  echo ""
  echo "---------------------------------------------------------------"
  printf "  %d de %d comprobaciones superadas\n" "$((TOTAL - FALLOS))" "${TOTAL}"
  echo "---------------------------------------------------------------"
fi

[ "${FALLOS}" -eq 0 ] || exit 1
