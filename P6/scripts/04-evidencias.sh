#!/usr/bin/env bash
# Recolecta las evidencias que pide la rubrica (criterio 2.2, 15 puntos):
#   - estado del clúster y sus nodos
#   - pods en ejecucion
#   - peticiones exitosas realizadas desde internet a la direccion publica
#
# Genera un Markdown con la salida real de cada comando, mas capturas PNG si
# la skill de screenshot esta disponible.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/00-variables.sh

OUT="docs/evidencias"
SHOTS="$OUT/capturas"
mkdir -p "$SHOTS"
LB="$(cat .direccion-publica 2>/dev/null || true)"
MD="$OUT/01-evidencias-despliegue.md"

run() { echo "\$ $*" >> "$MD"; eval "$@" >> "$MD" 2>&1 || true; }

{
  echo "# Evidencias de funcionamiento — Práctica 6"
  echo ""
  echo "Generado el $(date '+%Y-%m-%d %H:%M:%S %Z') con \`scripts/04-evidencias.sh\`."
  echo ""
  echo "Toda la salida de esta página proviene de la ejecución real de los comandos"
  echo "contra el clúster administrado; no hay salidas transcritas a mano."
  echo ""
} > "$MD"

echo "## 1. Clúster administrado y sus nodos" >> "$MD"
echo '```' >> "$MD"
run eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION"
echo "" >> "$MD"
run kubectl config current-context
echo "" >> "$MD"
run kubectl get nodes -o wide
echo '```' >> "$MD"
echo "" >> "$MD"

echo "## 2. Componentes en ejecución" >> "$MD"
echo '```' >> "$MD"
run kubectl get pods -n "$NAMESPACE" -o wide
echo "" >> "$MD"
run kubectl get deploy,sts,svc,pvc,hpa,cronjob -n "$NAMESPACE"
echo '```' >> "$MD"
echo "" >> "$MD"

echo "## 3. Almacenamiento con la StorageClass del proveedor" >> "$MD"
echo '```' >> "$MD"
run kubectl get storageclass
echo "" >> "$MD"
run kubectl get pv -o "custom-columns=NOMBRE:.metadata.name,CAPACIDAD:.spec.capacity.storage,SC:.spec.storageClassName,ESTADO:.status.phase"
echo '```' >> "$MD"
echo "" >> "$MD"

echo "## 4. Secretos gestionados dentro del clúster" >> "$MD"
echo '' >> "$MD"
echo "Se listan los nombres y el número de claves; **nunca los valores**." >> "$MD"
echo '```' >> "$MD"
run kubectl get secrets -n "$NAMESPACE" -o "custom-columns=NOMBRE:.metadata.name,TIPO:.type"
echo '```' >> "$MD"
echo "" >> "$MD"

echo "## 5. Peticiones desde internet a la dirección pública" >> "$MD"
if [ -n "$LB" ]; then
  echo "" >> "$MD"
  echo "Dirección pública del Network Load Balancer: \`http://$LB\`" >> "$MD"
  echo "" >> "$MD"
  echo '```' >> "$MD"
  run curl -s -o /dev/null -w "'GET / -> HTTP %{http_code} en %{time_total}s\n'" "http://$LB/"
  run curl -s -w "'\n-> HTTP %{http_code}\n'" "http://$LB/health/ready"
  echo "" >> "$MD"
  echo "# El DNS del balanceador resuelve a direcciones publicas de AWS:" >> "$MD"
  run getent hosts "$LB"
  echo '```' >> "$MD"
else
  echo "" >> "$MD"
  echo "> No se encontró \`.direccion-publica\`. Ejecutar antes \`scripts/03-desplegar.sh\`." >> "$MD"
fi
echo "" >> "$MD"

# Capturas de pantalla, si la skill esta instalada.
CAP="$HOME/.claude/skills/screenshot/scripts/capture.sh"
if [ -x "$CAP" ]; then
  echo "## 6. Capturas de pantalla" >> "$MD"
  echo "" >> "$MD"
  for r in "${@:-}"; do
    [ -z "$r" ] && continue
    f="$SHOTS/$r-$(date +%H%M%S).png"
    "$CAP" "$r" "$f" >/dev/null 2>&1 && {
      echo "![$r](capturas/$(basename "$f"))" >> "$MD"
      echo "" >> "$MD"
      echo "   capturado: $f"
    }
  done
fi

echo ""
echo ">> Evidencias escritas en $MD"
