{{/*
Expand the name of the chart.
*/}}
{{- define "match.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "match.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "match.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "match.labels" -}}
helm.sh/chart: {{ include "match.chart" . }}
{{ include "match.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "match.selectorLabels" -}}
app.kubernetes.io/name: {{ include "match.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "match.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "match.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate a consistent random password for the ingester user
*/}}
{{- define "match.ingesterPassword" -}}
{{- if and .Values.ingesterUser .Values.ingesterUser.password }}
{{- .Values.ingesterUser.password }}
{{- else }}
{{- $secretName := printf "%s-ingester-credentials" (include "match.fullname" .) }}
{{- $existingSecret := lookup "v1" "Secret" .Release.Namespace $secretName }}
{{- if $existingSecret }}
{{- index $existingSecret.data "password" | b64dec }}
{{- else }}
{{- printf "%s%s%s%s" (randAlpha 4) (randAlpha 4 | upper) (randNumeric 4) "!@#$" | shuffle }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate a consistent random password for the admin user
*/}}
{{- define "match.owningUserPassword" -}}
{{- if and .Values.owningUser .Values.owningUser.password }}
{{- .Values.owningUser.password }}
{{- else }}
{{- $secretName := printf "%s-owning-user-credentials" (include "match.fullname" .) }}
{{- $existingSecret := lookup "v1" "Secret" .Release.Namespace $secretName }}
{{- if $existingSecret }}
{{- index $existingSecret.data "password" | b64dec }}
{{- else }}
{{- printf "%s%s%s%s" (randAlpha 4) (randAlpha 4 | upper) (randNumeric 4) "!@#$" | shuffle }}
{{- end }}
{{- end }}
{{- end }}
{{- define "match.volumes" -}}
{{- if .Values.storage.sharedStorage.enabled }}
- name: {{ .Values.storage.sharedStorage.claimName }}
  persistentVolumeClaim:
    claimName: {{ .Values.storage.sharedStorage.claimName }}
{{- end }}
{{- if .Values.storage.tmpStorage.enabled }}
- name: tmp-storage
  emptyDir:
    {{- if .Values.storage.tmpStorage.sizeLimit }}
    sizeLimit: {{ .Values.storage.tmpStorage.sizeLimit }}
    {{- end }}
{{- end }}
{{- with .Values.volumes }}
{{ toYaml . }}
{{- end }}
{{- end }}
{{- define "match.volumeMounts" -}}
{{- if .Values.storage.sharedStorage.enabled }}
- name: {{ .Values.storage.sharedStorage.claimName }}
  mountPath: /app/storage
{{- end }}
{{- if .Values.storage.tmpStorage.enabled }}
- name: tmp-storage
  mountPath: /tmp
{{- end }}
{{- with .Values.volumeMounts }}
{{ toYaml . }}
{{- end }}
{{- end }}
