# Políticas de admisión — Kyverno

Tres políticas obligatorias, las que exige el enunciado. Todas en modo
`Enforce`: **rechazan** el recurso, no se limitan a anotarlo en un informe.

| Archivo | Política | Qué impide |
|---|---|---|
| [01-prohibir-latest.yaml](01-prohibir-latest.yaml) | `prohibir-etiqueta-latest` | Imágenes sin versión explícita |
| [02-exigir-limites.yaml](02-exigir-limites.yaml) | `exigir-limites-de-recursos` | Contenedores sin requests ni limits |
| [03-exigir-sin-root.yaml](03-exigir-sin-root.yaml) | `exigir-ejecucion-sin-root` | Contenedores privilegiados |

## Por qué `Enforce` y no `Audit`

En modo `Audit`, Kyverno deja crear el recurso y anota la violación en un
informe que nadie lee. La práctica exige demostrar un despliegue **rechazado**,
y un control que no puede bloquear no es un control: es documentación.

## Por qué `validate` y no `mutate`

Kyverno podría "arreglar" los manifiestos: sustituir `latest` por un digest,
inyectar los limits que faltan. Se rechaza a propósito. El objetivo no es que
el despliegue funcione de todos modos, sino que quede constancia de que alguien
intentó desplegar algo no trazable. **Una mutación silenciosa oculta el
problema; un rechazo lo documenta.**

## Relación con el LimitRange de Terraform

La política 2 y el LimitRange de [../terraform/platform/](../terraform/platform/)
parecen redundantes. No lo son, y ninguno sobra:

| Mecanismo | Qué hace | Para qué sirve |
|---|---|---|
| LimitRange | **Inyecta** los límites que faltan | Red de seguridad: evita que el pod sea rechazado por la ResourceQuota |
| Política 2 | **Rechaza** el manifiesto incompleto | Obliga al autor a declarar valores pensados para *su* servicio |

El LimitRange asigna valores por defecto que probablemente no son los adecuados
para esa carga concreta. La política es la que educa.

## Verificación sin clúster

Kyverno CLI evalúa las políticas contra manifiestos locales, sin necesidad de
tener el clúster encendido:

```bash
# Debe RECHAZAR el pod que viola las tres políticas
kyverno apply 01-prohibir-latest.yaml 02-exigir-limites.yaml 03-exigir-sin-root.yaml \
  --resource pruebas/pod-que-viola-las-politicas.yaml
```

Resultado esperado: `pass: 3, fail: 4` — las tres políticas detectan sus
violaciones.

La prueba inversa importa igual: las políticas no deben bloquear las cargas de
trabajo legítimas.

```bash
helm template sa-platform ../charts/sa-platform \
  -f ../charts/sa-platform/values.example.yaml -f ../charts/sa-platform/values-prod.yaml \
  --set namespace.name=sa-p8 --set postgresql.enabled=false --set rabbitmq.enabled=false \
  > /tmp/render.yaml
kyverno apply 0*.yaml --resource /tmp/render.yaml
```

Resultado obtenido sobre las 5 cargas de trabajo de la plataforma:
`pass: 28, fail: 0`.

## Evidencia del rechazo en el clúster

Con Kyverno instalado y las políticas aplicadas:

```bash
kubectl apply -f pruebas/pod-que-viola-las-politicas.yaml \
  2>&1 | tee ../docs/evidencias/politicas/rechazo-admision.txt
```

La salida es el error de admisión enumerando las reglas incumplidas. Ése es el
entregable *"evidencia de un despliegue rechazado"*.

## Nota sobre la API

Kyverno 1.19 marca `kyverno.io/v1 ClusterPolicy` como obsoleta en favor de las
nuevas `ValidatingPolicy` basadas en CEL. Se mantiene `ClusterPolicy`
deliberadamente: es la API estable y documentada, la que aparece en toda la
documentación oficial vigente, y la migración a CEL no aporta nada a los
objetivos de esta práctica. El aviso de obsolescencia no impide su
funcionamiento.
