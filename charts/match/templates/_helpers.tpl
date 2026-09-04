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
Init container that blocks pod startup until the database schema exists.
Prevents workers and web from entering CrashLoopBackOff on fresh installs
while db-prepare-initial is still running. On upgrades the schema already
exists so this exits immediately on the first attempt.
Skipped when useArgoSyncWaveAnnotations is true (ArgoCD manages ordering).
*/}}
{{- define "match.waitForSchema" -}}
{{- if not .Values.useArgoSyncWaveAnnotations }}
- name: wait-for-schema
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command:
    - sh
    - -c
    - |
      until PGPASSWORD="$DB_PASSWORD" psql -h "$DB_PRIMARY_HOST" -U "$DB_USERNAME" -d "$DB_DATABASE" \
        -c "SELECT 1 FROM schema_migrations LIMIT 1" > /dev/null 2>&1; do
        echo "waiting for schema to be ready..."
        sleep 5
      done
  env:
   {{- include "match.envVars" . | nindent 4 }}
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
  {{- if .Values.storage.tmpStorage.sizeLimit }}
  emptyDir:
    sizeLimit: {{ .Values.storage.tmpStorage.sizeLimit }}
  {{- else }}
  emptyDir: {}
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

{{/*
Validate that secret generation is not enabled when using ArgoCD
*/}}
{{- define "match.validateArgoSecretGeneration" -}}
{{- if and .Values.useArgoSyncWaveAnnotations (or .Values.secretKeys.secret.generate .Values.owningUser.secret.generate) }}
{{- fail "Error: Secret generation is not supported when using Argo (useArgoSyncWaveAnnotations=true). Argo does not support Helm's lookup() function. Please set all secret generation flags to false and provide pre-created Secrets." }}
{{- end }}
{{- end }}

{{/*
Generate a consistent random API secret key base for the first deploy using release name and namespace
*/}}
{{- define "match.apiSecretKeyBase" -}}
{{- $secretName := .Values.secretKeys.secret.name }}
{{- $existingSecret := lookup "v1" "Secret" .Release.Namespace $secretName }}
{{- if $existingSecret }}
{{- index $existingSecret.data "api_secret_key_base" | b64dec }}
{{- else }}
{{- printf "%s%s" (randAlphaNum 64 | sha256sum) (randAlphaNum 64 | sha256sum) }}
{{- end }}
{{- end }}

{{/*
Generate a consistent random secret key base for the first deploy using release name and namespace
*/}}
{{- define "match.secretKeyBase" -}}
{{- $secretName := .Values.secretKeys.secret.name }}
{{- $existingSecret := lookup "v1" "Secret" .Release.Namespace $secretName }}
{{- if $existingSecret }}
{{- index $existingSecret.data "secret_key_base" | b64dec }}
{{- else }}
{{- printf "%s%s" (randAlphaNum 64 | sha256sum) (randAlphaNum 64 | sha256sum) }}
{{- end }}
{{- end }}

{{/*
Generate a consistent random ingest credential encryption key for the first deploy using release name and namespace
*/}}
{{- define "match.ingestCredentialEncryptionKey" -}}
{{- $secretName := .Values.secretKeys.secret.name }}
{{- $existingSecret := lookup "v1" "Secret" .Release.Namespace $secretName }}
{{- if $existingSecret }}
{{- index $existingSecret.data "ingest_credential_encryption_key" | b64dec }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Generate a consistent random password for the owning user for the first deploy using release name and namespace
*/}}
{{- define "match.owningUserPassword" -}}
{{- $secretName := .Values.owningUser.secret.name }}
{{- $existingSecret := lookup "v1" "Secret" .Release.Namespace $secretName }}
{{- if $existingSecret }}
{{- index $existingSecret.data "password" | b64dec }}
{{- else }}
{{- (printf "%s%s%s%s%s" (randAlpha 12) (randAlpha 8 | upper) (randNumeric 6) "!@#" (randAlpha 4)) | shuffle }}
{{- end }}
{{- end }}

{{/*
Redis address for KEDA scaler triggers.

KEDA's redis scaler expects a bare "host:port" in `address` and fails with
"too many colons in address" if given a URL, whereas the application's own
Sidekiq client needs the full rediss:// URL. Both read the same value, so strip
the scheme here rather than in each trigger — a duplicated inline expression is
how scaled-worker.yaml previously drifted from scaled-job.yaml and left
generic-worker unable to scale.
*/}}
{{- define "match.kedaRedisAddress" -}}
{{- .Values.sidekiq.redisServerUrl | trimPrefix "rediss://" | trimPrefix "redis://" -}}
{{- end }}
