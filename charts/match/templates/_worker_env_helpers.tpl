{{- define "match.workerEnvVars" -}}
- name: AD_SIGNAL_DATABASE_POOL_SIZE
  value: "{{ mul .worker.sidekiqConcurrency 2 }}"
{{- end }}
