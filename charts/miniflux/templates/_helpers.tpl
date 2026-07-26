{{/*
Expand the name of the chart.
*/}}
{{- define "miniflux.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "miniflux.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart label.
*/}}
{{- define "miniflux.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "miniflux.labels" -}}
helm.sh/chart: {{ include "miniflux.chart" . }}
{{ include "miniflux.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/component: feed-reader
app.kubernetes.io/part-of: miniflux
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels. These land in an immutable Deployment selector, so they must
never include a value that changes between releases, such as the chart version.
*/}}
{{- define "miniflux.selectorLabels" -}}
app.kubernetes.io/name: {{ include "miniflux.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the secret holding sensitive values.
*/}}
{{- define "miniflux.secretName" -}}
{{- if .Values.existingSecret }}
{{- .Values.existingSecret }}
{{- else }}
{{- include "miniflux.fullname" . }}
{{- end }}
{{- end }}

{{/*
Secret keys. A chart-managed Secret always uses the canonical key names; an
existing Secret may use its own.
*/}}
{{- define "miniflux.databaseUrlKey" -}}
{{- if .Values.existingSecret }}
{{- .Values.existingSecretDatabaseUrlKey | default "DATABASE_URL" }}
{{- else }}
{{- "DATABASE_URL" }}
{{- end }}
{{- end }}

{{- define "miniflux.adminPasswordKey" -}}
{{- if .Values.existingSecret }}
{{- .Values.existingSecretAdminPasswordKey | default "ADMIN_PASSWORD" }}
{{- else }}
{{- "ADMIN_PASSWORD" }}
{{- end }}
{{- end }}

{{/*
Container image reference. A digest, when set, wins over the tag.
*/}}
{{- define "miniflux.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
{{- end }}
