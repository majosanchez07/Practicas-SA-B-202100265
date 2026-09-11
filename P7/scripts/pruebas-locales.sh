#!/usr/bin/env bash
# ==============================================================================
# pruebas-locales.sh — Ejecuta las mismas pruebas que la etapa 2 del pipeline.
#
# Sirve para verificar antes de hacer commit que el pipeline no va a fallar.
# Ejecuta exactamente los mismos comandos que el workflow: node --test para los
# servicios de Node y pytest para los de Python.
#
# Uso:  ./P7/scripts/pruebas-locales.sh
# ==============================================================================
set -uo pipefail

cd "$(dirname "$0")/.."
RAIZ="$(pwd)"

SERVICIOS_NODE=(api-gateway loans-service notifications-service)
SERVICIOS_PYTHON=(auth-service books-service)

fallos=0
declare -a resumen=()

echo "================================================================"
echo " Pruebas unitarias — Practica 7"
echo "================================================================"

for servicio in "${SERVICIOS_NODE[@]}"; do
  echo ""
  echo ">> ${servicio} (Node)"
  cd "${RAIZ}/services/${servicio}"

  [[ -d node_modules ]] || npm ci --no-audit --no-fund

  if npm test; then
    resumen+=("OK       ${servicio}")
  else
    resumen+=("FALLO    ${servicio}")
    fallos=$((fallos + 1))
  fi
done

for servicio in "${SERVICIOS_PYTHON[@]}"; do
  echo ""
  echo ">> ${servicio} (Python)"
  cd "${RAIZ}/services/${servicio}"

  # Un entorno virtual por servicio, igual que el aislamiento que da el runner.
  if [[ ! -d .venv ]]; then
    python3 -m venv .venv
    ./.venv/bin/pip install -q --upgrade pip
    ./.venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt
  fi

  if ./.venv/bin/python -m pytest; then
    resumen+=("OK       ${servicio}")
  else
    resumen+=("FALLO    ${servicio}")
    fallos=$((fallos + 1))
  fi
done

echo ""
echo "================================================================"
echo " Resumen"
echo "================================================================"
printf '%s\n' "${resumen[@]}"
echo ""

if (( fallos > 0 )); then
  echo "${fallos} servicio(s) con pruebas en rojo. El pipeline fallaria."
  exit 1
fi

echo "Todas las pruebas pasan. El pipeline deberia quedar en verde."
