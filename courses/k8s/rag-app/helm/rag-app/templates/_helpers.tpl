{{- define "rag-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rag-app.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rag-app.labels" -}}
app.kubernetes.io/name: {{ include "rag-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "rag-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rag-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
