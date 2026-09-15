#!/usr/bin/env bash
# ==============================================================================
# Verificacion: el pipeline de la Practica 8 no puede desplegar
#
# Maria Jose Tebalan Sanchez — 202100265
#
# La rubrica lo incluye como REQUISITO PARA OPTAR A LA CALIFICACION:
#
#   "Sin despliegue directo: ningun workflow ejecuta kubectl apply, kubectl set
#    image o helm upgrade contra el cluster, ni almacena kubeconfig."
#
# Comprobarlo automaticamente, y no solo por inspeccion visual, es lo que
# convierte la prohibicion en una garantia: si alguien anadiera manana un paso
# de despliegue directo, el pipeline fallaria aqui.
#
# Por que este script vive FUERA del workflow
# -------------------------------------------
# La primera version de esta comprobacion estaba escrita dentro del propio
# archivo del workflow, y fallaba siempre. El motivo es instructivo: los
# patrones de busqueda ("kubectl apply", "helm upgrade") aparecian literalmente
# en las lineas que los buscaban, de modo que el grep se encontraba a si mismo.
#
# Separar los patrones del archivo analizado elimina el falso positivo de raiz:
# este script nunca se analiza a si mismo, solo analiza los workflows.
#
# Uso:
#   ./verificar-sin-despliegue-directo.sh [archivo...]
#
# Sin argumentos analiza .github/workflows/p8-gitops.yml.
# ==============================================================================
set -uo pipefail

ARCHIVOS=("$@")
if [ ${#ARCHIVOS[@]} -eq 0 ]; then
  RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  ARCHIVOS=("${RAIZ}/.github/workflows/p8-gitops.yml")
fi

# Cada entrada: <expresion regular>|<descripcion legible>
#
# Los patrones se construyen concatenando fragmentos para que la cadena
# literal que se busca no aparezca completa en este archivo. Es una precaucion
# contra el mismo falso positivo que motivo este script, por si alguna vez se
# analizara el directorio de scripts.
PATRONES=(
  "kube""ctl[[:space:]]+apply|kubectl apply"
  "kube""ctl[[:space:]]+set[[:space:]]+image|kubectl set image"
  "kube""ctl[[:space:]]+delete|kubectl delete"
  "kube""ctl[[:space:]]+patch|kubectl patch"
  "kube""ctl[[:space:]]+create|kubectl create"
  "helm""[[:space:]]+upgrade|helm upgrade"
  "helm""[[:space:]]+install|helm install"
  "helm""[[:space:]]+rollback|helm rollback"
  "KUBE""CONFIG|variable KUBECONFIG"
  "kube""_?config[[:space:]]*:|declaracion de kubeconfig"
  "aws[[:space:]]+eks[[:space:]]+update-""kubeconfig|aws eks update-kubeconfig"
  "azure/k8s-""deploy|accion azure/k8s-deploy"
  "kind-""action|creacion de cluster kind"
  "argocd[[:space:]]+app[[:space:]]+sync|sincronizacion forzada de ArgoCD"
)

FALLOS=0

echo "Verificando ausencia de despliegue directo"
echo "Archivos analizados: ${ARCHIVOS[*]}"
echo ""

for entrada in "${PATRONES[@]}"; do
  patron="${entrada%%|*}"
  descripcion="${entrada#*|}"

  # Se excluyen las lineas de comentario del YAML: una mencion en la
  # documentacion del workflow no es un comando ejecutable.
  coincidencias="$(grep -nE "${patron}" "${ARCHIVOS[@]}" 2>/dev/null \
                   | grep -vE '^\s*[0-9]+:\s*#' \
                   | grep -vE '^[^:]+:[0-9]+:\s*#' || true)"

  if [ -n "${coincidencias}" ]; then
    echo "  FALLA   ${descripcion}"
    echo "${coincidencias}" | sed 's/^/          /'
    FALLOS=$((FALLOS + 1))
  else
    echo "  OK      sin ${descripcion}"
  fi
done

echo ""
if [ "${FALLOS}" -gt 0 ]; then
  echo "ERROR: se detectaron ${FALLOS} forma(s) de despliegue directo."
  echo "El enunciado prohibe que el pipeline aplique cambios al cluster."
  exit 1
fi

echo "Verificado: el pipeline no puede aplicar cambios al cluster."
echo "El unico componente que despliega es ArgoCD, desde dentro del cluster."
