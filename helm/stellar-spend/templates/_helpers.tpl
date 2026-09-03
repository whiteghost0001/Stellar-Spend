{{/*
Expand the chart name.
*/}}
{{- define "stellar-spend.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Full release name (release + chart, truncated at 63 chars).
*/}}
{{- define "stellar-spend.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "stellar-spend.labels" -}}
helm.sh/chart: {{ include "stellar-spend.name" . }}-{{ .Chart.Version | replace "+" "_" }}
{{ include "stellar-spend.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "stellar-spend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "stellar-spend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
