{{/*
================================================================================
Named templates compartidos por el chart padre y por todos los subcharts.

Al centralizarlos aqui, un cambio en la convencion de nombres o en las etiquetas
se propaga a los cinco microservicios, a los dos cronjobs y a las políticas de
red sin tener que editar cada plantilla por separado.
================================================================================
*/}}

{{/*
sa-platform.name
Nombre base del chart, sobrescribible con nameOverride.
*/}}
{{- define "sa-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
sa-platform.fullname
Nombre completo del release. Si el nombre del release ya contiene el del chart
no se duplica el prefijo, para evitar recursos llamados "sa-platform-sa-platform".
*/}}
{{- define "sa-platform.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
sa-platform.chart
Etiqueta de version del chart. El "+" no es valido en una etiqueta de
Kubernetes, por eso se reemplaza por "_".
*/}}
{{- define "sa-platform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
sa-platform.labels
Etiquetas comunes a todos los objetos del release.
*/}}
{{- define "sa-platform.labels" -}}
helm.sh/chart: {{ include "sa-platform.chart" . }}
{{ include "sa-platform.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: sa-platform
carne: {{ .Values.global.carne | default .Values.carne | quote }}
{{- end -}}

{{/*
sa-platform.selectorLabels
Subconjunto inmutable usado en los selectores. Nunca debe incluir la version:
el selector de un Deployment no se puede modificar despues de creado, de modo
que si llevara la version, cada helm upgrade fallaria.
*/}}
{{- define "sa-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sa-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
================================================================================
Helpers por servicio.
Reciben un diccionario con "root" (el contexto global) y "svc" (la clave del
servicio dentro de .Values.services), de modo que una sola plantilla sirve para
los cinco microservicios recorridos con range.
================================================================================
*/}}

{{/*
sa-platform.serviceName
Nombre completo de un microservicio: <release>-<servicio>.
*/}}
{{- define "sa-platform.serviceName" -}}
{{- printf "%s-%s" (include "sa-platform.fullname" .root) .svc | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
sa-platform.serviceLabels
Etiquetas completas de un microservicio concreto.
*/}}
{{- define "sa-platform.serviceLabels" -}}
{{ include "sa-platform.labels" .root }}
app.kubernetes.io/component: {{ .svc }}
{{- end -}}

{{/*
sa-platform.serviceSelectorLabels
Selector de un microservicio concreto. Se le agrega el componente para que cada
Deployment gobierne solo sus propios pods.
*/}}
{{- define "sa-platform.serviceSelectorLabels" -}}
{{ include "sa-platform.selectorLabels" .root }}
app.kubernetes.io/component: {{ .svc }}
{{- end -}}

{{/*
sa-platform.image
Construye la referencia de imagen de un servicio.
El tag se resuelve en cascada: el del propio servicio, si no el global del
release, y si tampoco existe, el appVersion del chart. Asi values-dev.yaml y
values-prod.yaml pueden fijar un tag distinto sin repetirlo cinco veces.
*/}}
{{- define "sa-platform.image" -}}
{{- $cfg := .cfg -}}
{{- $root := .root -}}
{{- /*
Orden de precedencia del registro, de mas especifico a mas general:
  1. image.registry del propio servicio
  2. .Values.imageRegistry  <- registro comun a los componentes DE ESTE chart
  3. .Values.global.imageRegistry

El paso 2 existe por una razon concreta: global.imageRegistry lo heredan tambien
los subcharts de Bitnami (postgresql y rabbitmq), de modo que usarlo para apuntar
a GHCR haria que esos dos buscaran su imagen dentro de mi repositorio, donde no
existe, y quedaran en ImagePullBackOff. imageRegistry es local a este chart y no
se propaga, asi que el pipeline lo usa para redirigir unicamente los siete
componentes propios.
*/}}
{{- $registry := $cfg.image.registry | default $root.Values.imageRegistry | default $root.Values.global.imageRegistry -}}
{{- $tag := $cfg.image.tag | default $root.Values.global.imageTag | default $root.Chart.AppVersion -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $cfg.image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $cfg.image.repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
sa-platform.serviceAccountName
ServiceAccount dedicado de cada carga de trabajo. El enunciado prohibe usar el
ServiceAccount "default", asi que nunca se devuelve ese valor.
*/}}
{{- define "sa-platform.serviceAccountName" -}}
{{- printf "%s-sa" (include "sa-platform.serviceName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
sa-platform.configMapName / sa-platform.secretName
Nombres del ConfigMap y del Secret compartidos por las cargas de trabajo.
*/}}
{{- define "sa-platform.configMapName" -}}
{{- printf "%s-config" (include "sa-platform.fullname" .) -}}
{{- end -}}

{{- define "sa-platform.secretName" -}}
{{- printf "%s-secret" (include "sa-platform.fullname" .) -}}
{{- end -}}

{{/*
sa-platform.postgresHost
Host del servicio de PostgreSQL desplegado como dependencia. El chart de Bitnami
nombra su servicio <release>-postgresql.
*/}}
{{- define "sa-platform.postgresHost" -}}
{{- printf "%s-postgresql" .Release.Name -}}
{{- end -}}

{{/*
sa-platform.rabbitmqHost
Host del servicio de RabbitMQ desplegado como dependencia.
*/}}
{{- define "sa-platform.rabbitmqHost" -}}
{{- printf "%s-rabbitmq" .Release.Name -}}
{{- end -}}

{{/*
sa-platform.databaseUrl
URL de conexion a PostgreSQL. Se construye a partir de las credenciales que
llegan por values, de modo que la cadena completa vive en el Secret y no
aparece escrita en ninguna plantilla.
El usuario es obligatorio: required corta la instalacion con un mensaje claro
en lugar de generar una URL invalida que solo fallaria al arrancar el pod.
*/}}
{{- define "sa-platform.databaseUrl" -}}
{{- $user := required "postgresql.auth.username es obligatorio" .Values.postgresql.auth.username -}}
{{- $pass := required "postgresql.auth.password es obligatorio (usar --set o un values propio, nunca versionarlo)" .Values.postgresql.auth.password -}}
{{- $db := required "postgresql.auth.database es obligatorio" .Values.postgresql.auth.database -}}
{{- printf "postgresql://%s:%s@%s:5432/%s" $user $pass (include "sa-platform.postgresHost" .) $db -}}
{{- end -}}

{{/*
sa-platform.rabbitmqUrl
URL de conexion al broker, construida con el mismo criterio que la anterior.
*/}}
{{- define "sa-platform.rabbitmqUrl" -}}
{{- $user := required "rabbitmq.auth.username es obligatorio" .Values.rabbitmq.auth.username -}}
{{- $pass := required "rabbitmq.auth.password es obligatorio (usar --set o un values propio, nunca versionarlo)" .Values.rabbitmq.auth.password -}}
{{- printf "amqp://%s:%s@%s:5672" $user $pass (include "sa-platform.rabbitmqHost" .) -}}
{{- end -}}
