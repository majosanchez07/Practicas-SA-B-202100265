# Práctica 8 — Entrega declarativa, progresiva y verificada

María José Tebalán Sánchez — 202100265
Software Avanzado B — Universidad de San Carlos de Guatemala

---

## Tabla de enlaces

Los nombres de los ítems son los de la sección 4.1 del enunciado, sin
modificar: esta tabla es el único documento que se utiliza para localizar la
evidencia, de modo que debe poder recorrerse contra el enunciado sin
traducciones.

| Ítem | Enlace o dato requerido |
|---|---|
| Repositorio GitOps | https://github.com/majosanchez07/Practicas-SA-B-202100265-gitops |
| Aplicación en ArgoCD | Aplicación: `sa-platform` — Namespace: `argocd` |
| Ejecución exitosa del pipeline | https://github.com/majosanchez07/Practicas-SA-B-202100265/actions/runs/35311531636 |
| Reversión automática | [docs/evidencias/rollouts/reversion-automatica.txt](docs/evidencias/rollouts/reversion-automatica.txt) · Rollout `sa-platform-api-gateway` en `sa-p8` · 66 s de recuperación |
| Despliegue rechazado por política | [docs/evidencias/politicas/rechazo.txt](docs/evidencias/politicas/rechazo.txt) |
| Bloqueo por vulnerabilidad crítica | _(pendiente)_ |
| Imagen firmada | `ghcr.io/majosanchez07/practicas-sa-b-202100265/p8-api-gateway:1.0.1` |
| Reporte de prueba de carga | [docs/evidencias/carga/reporte-carga.txt](docs/evidencias/carga/reporte-carga.txt) · 612 peticiones, 0% error, p95 122 ms |
| Video demostrativo | _(pendiente)_ |

---

## Documentación

| Documento | Contenido |
|---|---|
| [Documentación técnica](docs/documentacion-tecnica.md) | El problema, la solución y las decisiones de diseño |
| [Diagrama del flujo](docs/diagrama-flujo.md) | Recorrido completo con actores y puntos de validación |
| [Informe de incidente](docs/informe-incidente.md) | Análisis del fallo inducido |
| [Preguntas teóricas](docs/preguntas-teoricas.md) | Análisis de la implementación entregada |
| [Manual de demostraciones](docs/manual-demostraciones.md) | Procedimiento paso a paso de las cuatro demostraciones |
| [Guía de despliegue](docs/despliegue.md) | Procedimiento operativo completo |
| [Guion del video](docs/guion-video.md) | Guion y minutaje de la demostración |
| [Índice de evidencias](docs/evidencias/INDICE.md) | Todas las evidencias recogidas del entorno real |
| [Capturas de pantalla](docs/evidencias/capturas/INDICE-CAPTURAS.md) | 20 capturas del sistema funcionando |
| [Comandos de verificación](docs/comandos-verificacion.md) | Cómo comprobar cada criterio por cuenta propia |
| [Guía de revisión en vivo](docs/guia-revision-en-vivo.md) | Qué mostrar y en qué orden durante la calificación |

---

## Estructura

```
P8/
├── terraform/          Declaración de infraestructura
│   ├── cluster/        Entorno de ejecución: red, plano de control, nodos
│   └── platform/       Espacios de trabajo, cuotas, límites, permisos
├── charts/             Empaquetado de la aplicación
├── policies/           Normas de admisión y manifiesto de prueba
├── tests/              Pruebas de disponibilidad, funcionalidad y rendimiento
├── services/           Los cinco componentes de la aplicación
├── cronjobs/           Los dos procesos programados
├── scripts/            Verificación de ausencia de despliegue directo
└── docs/               Documentación y evidencias
```

---

## El cambio respecto de la práctica anterior

La automatización de la práctica anterior poseía credenciales de administración
del entorno y aplicaba los cambios directamente. En esta práctica **no puede
desplegar**: su capacidad máxima es proponer un cambio de versión en el
repositorio de declaración.

| | Anterior | Actual |
|---|---|---|
| Quién aplica los cambios | La automatización externa | Un componente interno del entorno |
| Credenciales del entorno | Las poseía la automatización | La automatización no tiene ninguna |
| Alcance de un cambio defectuoso | Totalidad de los usuarios | Como máximo, la etapa en curso |
| Reversión | Manual | Automática, sin intervención |
| Desviación del estado declarado | No se detectaba | Se detecta y se corrige sola |

Esa prohibición está **verificada automáticamente**, no solo declarada:

```bash
./scripts/verificar-sin-despliegue-directo.sh
```

El script se ejecuta como primera etapa de la automatización, antes de construir
ningún artefacto. Comprueba catorce patrones distintos de despliegue directo y
de uso de credenciales del entorno.

---

## Verificación sin desplegar

Todo lo siguiente se comprueba sin necesidad de tener el entorno encendido.

**Empaquetado válido en ambos ambientes**

```bash
helm dependency build charts/sa-platform
helm lint charts/sa-platform \
  -f charts/sa-platform/values.example.yaml \
  -f charts/sa-platform/values-prod.yaml --set namespace.name=sa-p8
```

**Las normas rechazan lo no conforme**

```bash
cd policies
kyverno apply 01-prohibir-latest.yaml 02-exigir-limites.yaml 03-exigir-sin-root.yaml \
  --resource pruebas/pod-que-viola-las-politicas.yaml
```

Resultado esperado: las tres normas detectan sus incumplimientos.

**Las normas no bloquean lo legítimo**

```bash
helm template sa-platform charts/sa-platform \
  -f charts/sa-platform/values.example.yaml \
  -f charts/sa-platform/values-prod.yaml \
  --set namespace.name=sa-p8 \
  --set postgresql.enabled=false --set rabbitmq.enabled=false > /tmp/render.yaml
kyverno apply policies/0*.yaml --resource /tmp/render.yaml
```

Resultado obtenido sobre las cinco cargas de trabajo: veintiocho comprobaciones
superadas, ninguna fallida.

**La declaración de infraestructura es válida**

```bash
cd terraform/cluster   && terraform init -backend=false && terraform validate
cd ../platform         && terraform init -backend=false && terraform validate
```

---

## Despliegue

El orden importa: la segunda capa de infraestructura necesita que la primera
exista.

```bash
# 1. Entorno de ejecución
cd terraform/cluster
terraform init && terraform plan -out=plan.tfplan && terraform apply plan.tfplan
eval "$(terraform output -raw comando_kubeconfig)"

# 2. Espacios de trabajo, cuotas, límites y permisos
cd ../platform
terraform init && terraform plan -out=plan.tfplan && terraform apply plan.tfplan

# 3. Componentes internos y aplicación
#    (ver docs/despliegue.md)
```

El detalle completo, incluida la instalación de los componentes internos y la
recolección de evidencias, está en [docs/despliegue.md](docs/despliegue.md).

---

## Costo y ciclo de vida del entorno

El entorno de ejecución tiene un costo aproximado de 0.26 dólares por hora
—unos 6.20 al día si se deja encendido—. No es necesario mantenerlo activo de
forma continua: se crea, se recoge la evidencia y se destruye, y se vuelve a
crear el día de la evaluación.

```bash
cd terraform/platform && terraform destroy
cd ../cluster         && terraform destroy
```

El desglose por recurso está en [terraform/README.md](terraform/README.md).

---

## Nota sobre la terminología

La documentación de esta práctica describe los componentes por su función
—motor de declaración, controlador de promoción, motor de admisión— en lugar de
por su nombre de producto. La correspondencia completa está en el anexo de la
[documentación técnica](docs/documentacion-tecnica.md#6-anexo-equivalencia-de-componentes).
