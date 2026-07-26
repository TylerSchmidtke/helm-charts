{{- define "radicle-seed.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "radicle-seed.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := include "radicle-seed.name" . }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "radicle-seed.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "radicle-seed.labels" -}}
helm.sh/chart: {{ include "radicle-seed.chart" . }}
{{ include "radicle-seed.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "radicle-seed.selectorLabels" -}}
app.kubernetes.io/name: {{ include "radicle-seed.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "radicle-seed.authSecretName" -}}
{{- default (include "radicle-seed.fullname" .) .Values.auth.existingSecret }}
{{- end }}

{{- define "radicle-seed.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}
{{- end }}

{{- define "radicle-seed.explorerImage" -}}
{{- if .Values.explorer.image.digest }}
{{- printf "%s@%s" .Values.explorer.image.repository .Values.explorer.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.explorer.image.repository .Values.explorer.image.tag }}
{{- end }}
{{- end }}

{{- define "radicle-seed.meilisearchImage" -}}
{{- if .Values.search.meilisearch.image.digest }}
{{- printf "%s@%s" .Values.search.meilisearch.image.repository .Values.search.meilisearch.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.search.meilisearch.image.repository .Values.search.meilisearch.image.tag }}
{{- end }}
{{- end }}

{{/*
Public HTTPS hostname Explorer advertises as its preferred seed. This is a
browser-resolvable DNS name, which node.alias is not: the alias is a Radicle
peer display name and defaults to "radicle-seed". Falling back to it produced
an unresolvable preferredSeeds entry, so prefer an explicit value, then the
first Ingress host, and only then the alias.
*/}}
{{- define "radicle-seed.explorerSeedHost" -}}
{{- if .Values.explorer.preferredSeedHost -}}
{{- .Values.explorer.preferredSeedHost -}}
{{- else if and .Values.ingress.enabled (gt (len .Values.ingress.hosts) 0) -}}
{{- (index .Values.ingress.hosts 0).host -}}
{{- else -}}
{{- .Values.node.alias -}}
{{- end -}}
{{- end }}
