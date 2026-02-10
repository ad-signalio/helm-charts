{{- define "match.envVars" -}}
- name: REDIS_SIDEKIQ_SERVER_URL
{{- if .Values.sidekiq.redisServerSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.sidekiq.redisServerSecret.name }}
      key: {{ .Values.sidekiq.redisServerSecret.key }}
{{- else if .Values.sidekiq.redisServerConfigMap }}
  valueFrom:
    configMapKeyRef:
      name: {{ .Values.sidekiq.redisServerConfigMap.name }}
      key: {{ .Values.sidekiq.redisServerConfigMap.key }}
{{- else }}
  value: "{{.Values.sidekiq.redisServerUrl }}"
{{- end}}
- name: REDIS_SIDEKIQ_CLIENT_URL
{{- if .Values.sidekiq.redisClientSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.sidekiq.redisClientSecret.name }}
      key: {{ .Values.sidekiq.redisClientSecret.key }}
{{- else if .Values.sidekiq.redisClientConfigMap }}
  valueFrom:
    configMapKeyRef:
      name: {{ .Values.sidekiq.redisClientConfigMap.name }}
      key: {{ .Values.sidekiq.redisClientConfigMap.key }}
{{- else }}
  value: "{{ .Values.sidekiq.redisClientUrl}}"
{{- end }}
- name: ENABLE_DYNAMIC_QUEUING
  value: "false"
- name: RAILS_ENV
  value: "{{.Values.rails_env}}"
- name: RAILS_SERVE_STATIC_FILES
  value: "1"
- name: AD_SIGNAL_ENVIRONMENT
  value: "external"
- name: RAILS_LOG_LEVEL
  value: "{{.Values.logLevel}}"
- name: DISABLE_SPRING
  value: "1"
- name: LOG_PATH_MODE
  value: "{{.Values.log_path_mode}}"
- name: LOG_PATH
  value: "{{.Values.log_path}}"
- name: RAILS_DEVELOPMENT_SECRET
  value: "kjsdjshbfjlshbefks"
- name: SLACK_API_TOKEN
  value: "shdbjhsbdfs"
- name: "RAILS_LOG_TO_STDOUT"
  value: "1"
{{- if or .Values.secretKeys.apiSecretKeyBase.generate .Values.secretKeys.apiSecretKeyBase.existingSecret }}
- name: API_SECRET_KEY_BASE
  valueFrom:
    secretKeyRef:
      {{- if .Values.secretKeys.apiSecretKeyBase.existingSecret }}
      name: {{ .Values.secretKeys.apiSecretKeyBase.existingSecret.name }}
      key: {{ .Values.secretKeys.apiSecretKeyBase.existingSecret.key }}
      {{- else }}
      name: {{ include "match.fullname" . }}-api-secrets
      key: apiSecretKeyBase
      {{- end }}
{{- end }}
{{- if or .Values.secretKeys.secretKeyBase.generate .Values.secretKeys.secretKeyBase.existingSecret }}
- name: SECRET_KEY_BASE
  valueFrom:
    secretKeyRef:
      {{- if .Values.secretKeys.secretKeyBase.existingSecret }}
      name: {{ .Values.secretKeys.secretKeyBase.existingSecret.name }}
      key: {{ .Values.secretKeys.secretKeyBase.existingSecret.key }}
      {{- else }}
      name: {{ include "match.fullname" . }}-api-secrets
      key: secretKeyBase
      {{- end }}
{{- end }}
{{- if or .Values.secretKeys.ingestCredentialEncryptionKey.generate .Values.secretKeys.ingestCredentialEncryptionKey.existingSecret }}
- name: INGEST_CREDENTIAL_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      {{- if .Values.secretKeys.ingestCredentialEncryptionKey.existingSecret }}
      name: {{ .Values.secretKeys.ingestCredentialEncryptionKey.existingSecret.name }}
      key: {{ .Values.secretKeys.ingestCredentialEncryptionKey.existingSecret.key }}
      {{- else }}
      name: {{ include "match.fullname" . }}-api-secrets
      key: ingestCredentialEncryptionKey
      {{- end }}
{{- end }}
- name: S3_PRIMARY_BUCKET
  value: "{{ .Values.s3.primaryBucket | default "adsignal-primary-bucket" }}"
- name: S3_REGION
  value: "{{ .Values.s3.region | default "us-east-1" }}"
- name: AWS_REGION
  value: "{{ .Values.s3.region | default "us-east-1" }}"
  {{- if .Values.domain }}
- name: ADSIGNAL_BASE_DOMAIN
  value: {{ .Values.domain }}
  {{- end }}
{{- if .Values.postgres.enabled }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgres.fullnameOverride | default (printf "%s-postgres" (include "match.fullname" .)) }}
      key: postgres-password
- name: DB_USERNAME
  value: {{ .Values.postgres.auth.username | default "matchdb" | quote }}
- name: DB_DATABASE
  value: {{ .Values.postgres.auth.database | default "matchdb" | quote }}
- name: DB_PRIMARY_HOST
  value: {{ .Values.postgres.fullnameOverride | default (printf "%s-postgres" (include "match.fullname" .)) }}
- name: DB_REPLICA_HOSTS
  value: {{ .Values.postgres.fullnameOverride | default (printf "%s-postgres" (include "match.fullname" .)) }}
{{- else }}
{{- if .Values.postgres.passwordSecret }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgres.passwordSecret.name }}
      key: {{ .Values.postgres.passwordSecret.key }}
{{- else }}
- name: DB_PASSWORD
  value: "{{ .Values.postgres.auth.password | default "" }}"
{{- end }}
{{ if .Values.postgres.userNameSecret}}
- name: DB_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgres.userNameSecret.name }}
      key: {{ .Values.postgres.userNameSecret.key }}
{{- else }}
- name: DB_USERNAME
  value: "{{ .Values.postgres.auth.username | default "" }}"
{{- end }}
{{ if .Values.postgres.dbNameSecret }}
- name: DB_DATABASE
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgres.dbNameSecret.name }}
      key: {{ .Values.postgres.dbNameSecret.key }}
{{- else }}
- name: DB_DATABASE
  value: "{{ .Values.postgres.auth.database | default "matchdb" }}"
{{- end }}
{{- if .Values.postgres.dbPrimaryHostSecret }}
- name: DB_PRIMARY_HOST
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgres.dbPrimaryHostSecret.name }}
      key: {{ .Values.postgres.dbPrimaryHostSecret.key }}
- name: DB_REPLICA_HOSTS
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgres.dbPrimaryHostSecret.name }}
      key: {{ .Values.postgres.dbPrimaryHostSecret.key }}
{{- else}}
- name: DB_PRIMARY_HOST
  value: "{{ .Values.postgres.primaryHost }}"
- name: DB_REPLICA_HOSTS
  value: "{{ .Values.postgres.primaryHost }}"
{{- end }}
{{- if .Values.postgres.dbPortSecret }}
- name: DB_PORT
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgres.dbPortSecret.name }}
      key: {{ .Values.postgres.dbPortSecret.key }}
{{- else }}
- name: DB_PORT
  value: "{{ .Values.postgres.port | default "5432" }}"
{{- end }}
{{- end }}
- name: REDIS_USE_SENTINEL
  value: "{{ .Values.redis.useSentinel | default "false" }}"
{{- if .Values.smtp.enabled }}
- name: SMTP_ADDRESS
  valueFrom:
    secretKeyRef:
      name: {{ .Values.smtp.secret.name }}
      key: SMTP_ADDRESS
- name: SMTP_DOMAIN
  valueFrom:
    secretKeyRef:
      name: {{ .Values.smtp.secret.name }}
      key: SMTP_DOMAIN
- name: SMTP_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.smtp.secret.name }}
      key: SMTP_PASSWORD
- name: SMTP_PORT
  valueFrom:
    secretKeyRef:
      name: {{ .Values.smtp.secret.name }}
      key: SMTP_PORT
- name: SMTP_USER_NAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.smtp.secret.name }}
      key: SMTP_USER_NAME
- name: MAILER_DEFAULT_FROM
  valueFrom:
    secretKeyRef:
      name: {{ .Values.smtp.secret.name }}
      key: MAILER_DEFAULT_FROM
{{- end }}
{{- if .Values.honeybadger }}
- name: HONEYBADGER_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.honeybadger.secretName }}
      key: {{ .Values.honeybadger.secretKey }}
- name: HONEYBADGER_ENV
  value: "{{ required "honeybadger.environment is required. Please provide your Honeybadger environment name in values.yaml" .Values.honeybadger.environment }}"
{{- end }}
{{- range $extraEnv := .Values.extraEnvs }}
- name: {{ $extraEnv.name }}
  value: {{ $extraEnv.value | quote }}
{{- end }}
{{- range $secretEnv := .Values.extraEnvSecrets }}
- name: {{ $secretEnv.name }}
  valueFrom:
    secretKeyRef:
      name: {{ $secretEnv.secretName }}
      key: {{ $secretEnv.secretKey }}
{{- end }}
{{- if eq .Values.metrics.enabled true }}
- name: PROMETHEUS_EXPORTER_PORT
  value: "{{ .Values.metrics.metricsPort }}"
{{- else }}
{{- end }}
{{- if .Values.storage.tmpStorage.enabled }}
{{- if not (hasPrefix "/tmp" .Values.storage.tmpStorage.path) }}
{{- fail "storage.tmpStorage.path must be located in /tmp directory" }}
{{- end }}
- name: AD_SIGNAL_TMPDIR
  value: {{ .Values.storage.tmpStorage.path }}
{{- end }}
{{- end }}

# Only added to db:prepare job pods
{{- define "match.owningUserEnvVars" -}}
{{- if .Values.owningUser }}
- name: OWNING_USER_EMAIL
  value: "{{ .Values.owningUser.email }}"
- name: OWNING_USER_FIRSTNAME
  value: "{{ .Values.owningUser.firstName }}"
- name: OWNING_USER_LASTNAME
  value: "{{ .Values.owningUser.lastName }}"
- name: OWNING_USER_ROLES
  value: email_and_password
- name: OWNING_ORGANISATION_NAME
  value: "{{ .Values.owningUser.organisationName }}"
- name: OWNING_USER_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "match.fullname" . }}-owning-user-credentials
      key: password
{{- end }}
{{- end }}

