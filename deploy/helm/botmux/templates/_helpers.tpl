{{- define "botmux.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- define "botmux.fullname" -}}
{{- default (include "botmux.name" .) .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- define "botmux.labels" -}}
app.kubernetes.io/name: {{ include "botmux.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}
{{- define "botmux.serviceAccountName" -}}
{{- default (include "botmux.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}
{{- define "botmux.credentialsSecretName" -}}
{{- default (printf "%s-credentials" (include "botmux.fullname" .)) .Values.credentials.existingSecret -}}
{{- end -}}
