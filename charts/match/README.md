<!---
title: Match Self Hosted Helm Chart
folder: "Technical Documentation"
status: 2
-->
<!-- AUTO-GENERATED — do not edit. Source: docs/README.md + README.md.gotmpl. Regenerate with: helm-docs -->

![Version: 2.0.1](https://img.shields.io/badge/Version-2.0.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.0.0](https://img.shields.io/badge/AppVersion-2.0.0-informational?style=flat-square)

Snicket Labs Match Self Hosted

**Homepage:** <https://snicketlabs.io>

# Match Self Hosted Helm Chart

## Upgrading

See [UPGRADING.md](UPGRADING.md) for version-specific upgrade instructions.

## Overview

This chart will install a self hosted Match service.

It is strongly suggested that you run this chart on a Kubernetes cluster dedicated to match. We provide a reference implementation suitable
for AWS [here](https://github.com/ad-signalio/match-reference-architecture)

## Prerequisites

A Kubernetes cluster (1.32+ for KEDA based autoscaling) with the following facilities:

### ReadWriteMany PVC Location

The application requires a shared Kubernetes ReadWriteMany Persistent Volume Claim across all pods to provide scratch space for the ingest and processing of
content into the system. Examples of this include AWS EFS, NFS and AssureFile.

`ReadWriteOnce` Persistent Volumes such as AWS EBS and Azure Disk are NOT suitable.

See the Kubernetes Persistent Volumes [Documentation](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) for more details.

For example, to use separately provisioned Persistent Volume named "customer-provided-pvc" for shared storage:

```
storage:
  sharedStorage:
    enabled: true
    claimName: "customer-provided-pvc"
    storageClassName: "customer-provided-pvc"
    size: 45000Gi
```

EFS mounts should, if possible, have permissions set to the application user id (nonroot):

```yaml
parameters:
  directoryPerms: "755"
  ...
  gid: "65532"
  uid: "65532"
```

nonroot (65532) is a standard convention for "distroless" and hardened images

#### Sizing the Volume
The shared storage will hold temporary copies of ingested content files during processing and should be sized according to the number of workers and size of content.

> Please consult with Ad-Signal technical services for sizing recommendations.

### Writeable /tmp Directory

The tmp directory should be 1.5 x the size of the maximum Content.

The application requires a writable `/tmp` directory to use as temporary space while processing content.

By default a disk backed `emptyDir` is used. If the operator wishes to specify a different configuration this can be modified in `.Values.volumes`. It is recommended that this is disk rather than memory backed as the system may store large content files in this location.

```
storage:
  ...
  tmpStorage:
    emptyDir:
      enabled: true
      sizeLimit: 200Gi
```

> Please consult with Ad-Signal technical services for sizing recommendations.

#### Entrypoint

Note: The match image includes an entrypoint script that handles the setting of permissions for the emptyDir volumes.

### S3 Buckets

The application makes use of two types of S3 buckets:

- **Primary Bucket**: This is the main storage bucket for the application where artifacts such as thumbnails or proxy videos are stored.

- **Content Bucket**: These are buckets containing the source media files that you wish to ingest into the system.

### S3-Compatible Primary Storage (Non-AWS)

By default Match uses AWS S3 for its primary storage (thumbnails, proxy videos, and other artifacts), authenticated via IRSA. If you are running on-premises or on a cloud that provides an S3-compatible object store (e.g. Ceph RGW, MinIO, GCS S3-interop), you can point Match at that instead.

Configure the following `s3` values in your values file. Each value sets a corresponding environment variable that the application reads at runtime:

| Value | Env var set | Required | Description |
|---|---|---|---|
| `s3.primaryBucket` | `S3_PRIMARY_BUCKET` | Yes | Name of the bucket to use for primary storage |
| `s3.region` | `COMPATIBLE_S3_REGION`, `AWS_REGION` | No | Region string — most non-AWS stores ignore this, but the SDK requires it (default: `us-east-1`) |
| `s3.compatibleEndpoint` | `COMPATIBLE_ENDPOINT_URL_S3` | Yes | Full URL of the S3-compatible endpoint that pods use for all S3 operations (e.g. `http://my-ceph-rgw:80`) |
| `s3.compatiblePublicEndpoint` | `COMPATIBLE_PUBLIC_ENDPOINT_URL_S3` | No | Browser-reachable URL for the same store, when it differs from `s3.compatibleEndpoint` (see below) |
| `s3.compatibleCredentialsSecret` | — | Yes | Name of a Kubernetes Secret containing HMAC credentials (sets `COMPATIBLE_S3_ACCESS_KEY` / `COMPATIBLE_S3_SECRET_KEY`) |
| `s3.compatibleAccessKeyField` | — | No | Key name within `compatibleCredentialsSecret` for the access key ID (default: `access_key_id`) |
| `s3.compatibleSecretKeyField` | — | No | Key name within `compatibleCredentialsSecret` for the secret access key (default: `secret_access_key`) |
| `s3.compatibleForcePathStyle` | `COMPATIBLE_S3_FORCE_PATH_STYLE` | No | Use path-style S3 URLs — `"true"` or `"false"` (default: `"true"`). Required by Ceph, MinIO, and GCS S3 interop. Only set to `"false"` if your store explicitly uses virtual-hosted style URLs. |

These values only take effect when `s3.compatibleEndpoint` is set. When it is not set, Match falls back to AWS S3 via IRSA with no static credentials required.

#### GCS (Google Cloud Storage S3-interop) example

```yaml
s3:
  primaryBucket: my-gcs-bucket-name
  region: "auto"
  compatibleEndpoint: "https://storage.googleapis.com"
  compatibleCredentialsSecret: match-gcs-hmac-credentials   # Secret with keys access_key_id / secret_access_key
```

GCS S3-interop uses a single endpoint reachable from both pods and browsers, so `compatiblePublicEndpoint` is not required.

#### Ceph / MinIO (in-cluster) example

```yaml
s3:
  primaryBucket: my-bucket-name
  region: "us-east-1"
  compatibleEndpoint: "http://my-object-store.internal:80"
  compatibleCredentialsSecret: my-s3-credentials   # Secret with keys access_key_id / secret_access_key
```

If your credentials Secret uses different key names (e.g. a Rook OBC-created Secret uses `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`), override them:

```yaml
s3:
  primaryBucket: my-bucket-name
  region: "us-east-1"
  compatibleEndpoint: "http://rook-ceph-rgw.rook-ceph.svc:80"
  compatibleCredentialsSecret: my-obc-secret
  compatibleAccessKeyField: "AWS_ACCESS_KEY_ID"
  compatibleSecretKeyField: "AWS_SECRET_ACCESS_KEY"
```

#### Split internal/external endpoint (`s3.compatiblePublicEndpoint`)

If the endpoint pods use to reach your object store is not reachable from browsers (for example a Ceph RGW exposed only as a Kubernetes ClusterIP service), presigned URLs embedded in page responses will fail in the browser.

Set `s3.compatiblePublicEndpoint` to a URL that browsers can reach (for example a MetalLB LoadBalancer IP or a hostname routable over VPN). Match will continue using `s3.compatibleEndpoint` for all pod-to-S3 operations and will use `s3.compatiblePublicEndpoint` only when generating presigned URLs returned to clients.

```yaml
s3:
  primaryBucket: my-bucket-name
  compatibleEndpoint: "http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80"  # internal ClusterIP
  compatiblePublicEndpoint: "http://10.35.7.108"  # MetalLB LoadBalancer IP, reachable from browsers
  compatibleCredentialsSecret: my-s3-credentials
```

If `COMPATIBLE_PUBLIC_ENDPOINT_URL_S3` is not set, presigned URLs use the same host as `COMPATIBLE_ENDPOINT_URL_S3`. This is correct for any setup where the object store endpoint is already reachable from browsers.

#### Alternatives to the split endpoint

`COMPATIBLE_PUBLIC_ENDPOINT_URL_S3` is only needed when your primary S3-compatible store is deployed inside the cluster (or otherwise has a different address for pods than for browser clients). This is typical of in-cluster Ceph RGW, MinIO, or similar stores exposed only via a ClusterIP service. If your object store already has a single address reachable from both pods and browsers — for example, an external MinIO instance or a managed S3-compatible service — you can omit `COMPATIBLE_PUBLIC_ENDPOINT_URL_S3` entirely.

Where a split is unavoidable, the following infrastructure options let you collapse it to a single address, which is preferable because the split-endpoint path patches Rails' presigned URL generation and could be affected by future Rails upgrades.

**Option A — Use the LoadBalancer IP for everything (simplest)**

If you are already exposing your object store via a LoadBalancer (e.g. MetalLB), set `s3.compatibleEndpoint` to that IP and omit `s3.compatiblePublicEndpoint`:

```yaml
s3:
  compatibleEndpoint: "http://10.35.7.108"   # LoadBalancer IP — reachable from both pods and browsers
```

Pod traffic to the LoadBalancer IP is typically handled by kube-proxy DNAT rules without leaving the cluster. Verify this works on your CNI before relying on it — on some configurations traffic will physically hairpin out of the cluster and back in, which adds latency but still works.

**Option B — DNS split-horizon**

Configure a single hostname (e.g. `s3.cluster.example.com`) that resolves to the object store's ClusterIP internally (via a CoreDNS override) and to the LoadBalancer IP externally (via VPN or external DNS). Both pods and browsers use the same hostname; no split endpoint config is needed. This avoids any hairpin and is the most efficient option, but requires coordinating cluster DNS and external/VPN DNS.

**Option C — Ingress with a real hostname and TLS**

Put an NGINX or Traefik ingress in front of your object store, backed by a DNS record and TLS certificate. Both pods and browsers use `https://s3.customer.example.com`. This is the most robust long-term option and is recommended if your deployment already has a working ingress controller and certificate management.

#### What breaks if COMPATIBLE_PUBLIC_ENDPOINT_URL_S3 is misconfigured

Only operations that send a presigned URL to a browser are affected:

- **Manual file upload via the UI** — fails with a CORS or DNS error (browser cannot PUT to the presigned URL)
- **Video and media playback in the UI** — fails to load (presigned GET URL contains the wrong host)

Operations that are unaffected (all server-side, no presigned URLs sent to browsers):

- API material creation via `media.url` — the server fetches the file directly, no presigned URL involved
- Ingest source scanning and auto-ingest
- All other background processing

Customers who create materials exclusively via the API (providing a source URL rather than uploading a file) do not need `COMPATIBLE_PUBLIC_ENDPOINT_URL_S3` and are unaffected if it is absent or misconfigured.

#### Bucket CORS configuration

Match uploads files directly from the browser to the object store using presigned PUT URLs. The bucket must have a CORS policy that allows requests from the Match domain, otherwise uploads will fail with a 403 CORS error.

Set the CORS policy using the AWS CLI (or any S3-compatible client) against your public endpoint, replacing `https://match.example.com` with your `domain` value:

```bash
aws s3api put-bucket-cors \
  --endpoint-url <your-s3.compatiblePublicEndpoint-or-s3.compatibleEndpoint> \
  --bucket <your-bucket-name> \
  --region <your-region> \
  --cors-configuration '{
    "CORSRules": [{
      "AllowedOrigins": ["https://match.example.com"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }]
  }'
```

This only needs to be run once per bucket. It persists in the object store independently of Helm deployments, but must be re-applied if the bucket is recreated.

> AWS S3 users should configure CORS via the bucket policy in the reference architecture Terraform rather than the CLI.

### Optional Content via S3 Compatible API

Content to ingest may be provided to the application via an S3 compatible endpoint.
Static Access Keys and Secret credentials to access an S3 compatible endpoint may be provided in Match's web interface.

#### Credentials via AWS IAM with Kubernetes Service Account (IRSA)

For content in an AWS S3 bucket an IAM Role assumable by a Kubernetes service account (IRSA) in an EKS pod may also be used by providing a IAM role ARN to annotate
the Service Account with.  See the AWS IAM Roles for service accounts [documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) for further information on how to configure the IAM role and EKS cluster.

```
serviceAccount:
  annotations:
   eks.amazonaws.com/role-arn: "arn:aws:iam::111122223333:role/my-role"
```

## Postgres Database

> It's is HIGHLY recommended you provide your own Postgres Database and backups using a service such as AWS RDS.

Configure access to an externally managed database as below:

```
postgres:
  enabled: false
  database: matchdb
  username: matchdb
  primaryHost: my-external-database.example.internal
  port: 5432
  passwordSecret
    name: match-postgres-password # The name of the secret that contains the Postgres password.
    key: password # The key in the secret that contains the Postgres password.
```

An example secret to provide the password to an externally managed Postgres.

```
apiVersion: v1
kind: Secret
metadata:
  name: match-postgres-password
type: Opaque
data:
  password: bXlfc3VwZXJfc2VjcmV0X3Bhc3N3b3Jk== # Base64 encoded password
```

### Provisioning Postgres on the Kubernetes Cluster

Optionally the chart can install a Postgres database on your Kubernetes cluster using the CloudPirates OpenSource [Postgres Helm Chart](https://github.com/CloudPirates-io/helm-charts/tree/main/charts/postgres).

> ** WARNING **
> This database is NOT suitable for production use in an unmodified form. Backups, nor High Availability or resiliency are not configured.

```
postgres:
  enabled: true
```

## Redis

> It's is **HIGHLY** recommended you provide your own Redis or compatible Database using a service such as AWS ElasticCache.

Configure access to an externally managed redis as below:

```
redis:
  enabled: false
sidekiq:
  redisServerUrl: rediss://redis.external-domain.tld:6379/
```

### Provisioning Redis on the Kubernetes Cluster

Optionally the chart can install a Redis database on your Kubernetes cluster using the CloudPirates OpenSource [Redis Helm Chart](https://github.com/CloudPirates-io/helm-charts/tree/main/charts/redis).

> ** WARNING **
> This database is NOT suitable for production use in an unmodified form as High Availability or resiliency are **NOT** configured.

```
redis:
  enabled: true
```

## KEDA Autoscaling

Match supports [KEDA (Kubernetes Event Driven Autoscaling)](https://keda.sh/) to dynamically scale Sidekiq workers based on Redis queue depth. This provides cost-effective scaling by creating pods on-demand when work is available and scaling to zero when queues are empty.

### Prerequisites

**KEDA Installation Required**

KEDA must be installed on your Kubernetes cluster before enabling autoscaling. Match supports KEDA v2.x.

Install KEDA using Helm:

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace
```

Or follow the [KEDA installation documentation](https://keda.sh/docs/latest/deploy/).

**Kubernetes Version**

- Kubernetes 1.32+ is required as Match needs sidecar Job support.

### Enabling KEDA Autoscaling

Enable KEDA-based autoscaling in your values:

```yaml
kedaAutoScaling:
  enabled: true
  terminationGracePeriodSeconds: 30
  redis:
    pollingInterval: 10  # Check queue depth every 10 seconds
    port: 6379
    enabledTLS: true
    databaseIndex: 0
```

When `kedaAutoScaling.enabled` is `true`:
- **scaledJobs** and **scaledObjects** configurations are active
- **workers** (traditional static deployments) are disabled

When `kedaAutoScaling.enabled` is `false`:
- **workers** configurations are active
- **scaledJobs** and **scaledObjects** are disabled

### Redis Connection Configuration

KEDA needs to connect to your Redis instance to monitor queue depths. There are two methods:

#### Method 1: Direct Connection (Simple)

Use the existing Sidekiq Redis URL for KEDA triggers:

```yaml
kedaAutoScaling:
  enabled: true
  redis:
    authenticationRef:
      enabled: false  # Disables TriggerAuthentication, uses direct URL

sidekiq:
  redisServerUrl: rediss://redis.external-domain.tld:6379/
```

KEDA will extract the host from `sidekiq.redisServerUrl` for monitoring.

#### Method 2: KEDA TriggerAuthentication (Recommended for Production)

For better security and separation of concerns, use KEDA's TriggerAuthentication resource:

```yaml
kedaAutoScaling:
  enabled: true
  redis:
    authenticationRef:
      enabled: true
      name: keda-trigger-auth-redis
```

Create a secret containing Redis credentials:

```bash
kubectl create secret generic keda-redis-secret \
  --namespace match \
  --from-literal=host=redis.external-domain.tld \
  --from-literal=password=your-redis-password
```

Then create a TriggerAuthentication resource:

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-trigger-auth-redis
  namespace: match
spec:
  secretTargetRef:
    - parameter: host
      name: keda-redis-secret
      key: host
    - parameter: password
      name: keda-redis-secret
      key: password
```

This approach keeps Redis credentials separate and allows different authentication for KEDA vs. application access.

### Worker Types

Match provides two types of autoscaled workers:

**ScaledJobs (One-and-Done Pattern)**
- Best for CPU-intensive, long-running, or variable-duration tasks (e.g., video fingerprinting, transcoding)
- Creates ephemeral pods that process exactly one job then terminate
- Processes ONE Sidekiq queue per scaledJob
- Scales from 0 to maxReplicaCount based on queue depth

**ScaledObjects (HPA-like Pattern)**
- Best for lightweight, fast-processing tasks with multiple related queues
- Long-running worker deployments that scale similar to HorizontalPodAutoscaler
- Can process MULTIPLE Sidekiq queues per worker with configurable concurrency
- Scales between minReplicaCount and maxReplicaCount based on aggregate queue depth

Initial autoscaling configurations for different deployment sizes can be found in the `environment-sizes/` directory (e.g., `environment-sizes/small/small.yaml`).

### Values File Merging

This chart uses **Helm's deep merge** feature to combine multiple values files. When you deploy with multiple `-f` flags:

```bash
helm install ... --values your-custom-values.yaml -f environment-sizes/small/small.yaml
```

Helm merges the values files from left to right, where each file can override specific fields from previous files. The key behavior:

- **Deep merge for objects/maps**: Only the specific fields you define in later files are overridden; all other fields are preserved
- **Complete replacement for arrays**: Lists are replaced entirely, not merged

**Example**: The base `values.yaml` defines complete scaledJob configurations including resources, queues, timeouts, and `maxReplicaCount`. Environment-specific files (like `environment-sizes/small/small.yaml`) override **only** the `maxReplicaCount` field:

```yaml
# values.yaml (base configuration)
scaledJobs:
  fingerprinter-video:
    enabled: true
    maxReplicaCount: 2
    resources:
      requests:
        cpu: "0.5"
        memory: 0.7Gi
    sideKiqQueue: video_match_frames_native_fingerprint_tasks
    activeDeadlineSeconds: 3600

# environment-sizes/medium/medium.yaml (override)
scaledJobs:
  fingerprinter-video:
    maxReplicaCount: 4  # Override only this field

# Result after merge: maxReplicaCount is 4, all other fields preserved from values.yaml
```

This allows environment-specific files to adjust scaling limits without duplicating resource allocations, queue configurations, or other settings. The sizing multipliers are:
- **small.yaml**: 1x baseline (matches `values.yaml` defaults)
- **medium.yaml**: 2x baseline
- **large.yaml**: 3x baseline

## Image Pull Secrets

Match images and the Helm chart are hosted on the Snicketlabs registry at `registry.snicketlabs.io`. Access is controlled by a personal access token generated at **https://deploy.snicketlabs.io/settings/access-tokens**.

Log in to the registry with your token (required before pulling the Helm chart):

```bash
helm registry login registry.snicketlabs.io \
  --username ignored \
  --password <your-access-token>
```

Create a Kubernetes image pull secret in the namespace you are deploying to:

```bash
kubectl -n match create secret docker-registry matchcredentials \
  --docker-server=registry.snicketlabs.io \
  --docker-password=<your-access-token>
```

Then reference the secret in your values file:

```yaml
imagePullSecrets:
  - name: "matchcredentials"
```

> We recommend using a secret management solution such as AWS Secrets Manager CSI Driver, External Secrets Operator, or Vault to manage this credential in production.

## Ingress and Domain

To allow access to Match's user interface and API an Ingress must be configured, the ingress should provide TLS termination with certificates trusted by any clients you wish to connect to the interface.

This is an example ingress configuration using the AWS Load Balancer Controller.

```
ingress:
  enabled: true
  className: "alb"
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123123123:certificate/a11111-11111-11111-1111-1111
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/success-codes: "200-402"
    # Match performs long-running comparison requests. The ALB default idle
    # timeout of 60s may cause 504 timeout errors on these requests. Increase to
    # at least 300s (5 minutes) to allow comparisons to complete.
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=300

  hosts:
    - host: match.company.example.com
      paths:
        - path: /
          pathType: Prefix
```

The application domain must be configured the same as the Ingress.

```
domain: match.company.example.com
```

### EKS Auto Mode

On clusters running EKS Auto Mode the built-in `eks.amazonaws.com/alb` controller is used instead of the standalone AWS Load Balancer Controller. In this mode, ALB annotations such as `alb.ingress.kubernetes.io/load-balancer-attributes` are **not supported** — they are silently ignored.

Use `ingress.ingressClassParams` to create an `IngressClassParams` resource instead, if your cluster does not already have one configured.

```yaml
ingress:
  enabled: true
  className: "match-alb"
  annotations:
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123123123:certificate/a11111-11111-11111-1111-1111
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /up
    alb.ingress.kubernetes.io/success-codes: "200-402"
  hosts:
    - host: match.company.example.com
      paths:
        - path: /
          pathType: Prefix

  # EKS Auto Mode: replaces the load-balancer-attributes annotation (which is ignored).
  ingressClassParams:
    create: true
    scheme: internet-facing
    loadBalancerAttributes:
      - key: idle_timeout.timeout_seconds
        value: "300"
```

Match is intended to run on a dedicated cluster. `IngressClassParams` is cluster-scoped, so if you share a cluster across environments, only one environment should set `ingressClassParams.create: true` for a given `className`.

### DNS

A DNS entry must be configured to match the `domain` value pointing to the Ingress service providing TLS termination.

## Monitoring
### Customer Responsibilities Checklist

Before enabling monitoring, ensure you provide:
- Persistent storage (minimum 10Gi) for Prometheus, Grafana, and Loki (if enabled)
- Backup configuration for all persistent monitoring data (PVCs)
- Ingress and DNS configuration for accessing dashboards
- IAM roles and secrets for AWS integrations (CloudWatch, RDS, Redis, S3, etc.)
- Secret management for sensitive credentials (e.g., database, Redis, SMTP)

### PodMonitor and ServiceMonitor

The chart uses Prometheus PodMonitor and ServiceMonitor resources to automatically discover and scrape metrics from pods and services. This ensures metrics collection adapts as pods are created, scaled, or replaced, providing reliable observability for all workloads.

If your cluster does not include support for `PodMonitor` or `ServiceMonitor` objects or you have not set `monitoring.enabled = true` you may disable them by setting `metrics.enabled = false`

### Backup Guidance

If you enable persistence for Prometheus or Grafana, ensure you back up the associated PVCs regularly. For more information, see [Kubernetes Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) or your cloud provider's backup tools.

### Troubleshooting

- **No metrics in dashboards:** Check that PodMonitors/ServiceMonitors are deployed and Prometheus is scraping the correct endpoints.
- **Dashboards not loading:** Ensure Grafana is running and accessible via ingress.
- **Storage full:** Increase PVC size or clean up old data.
- **No logs:** Verify your log aggregation solution is running and pods are configured to emit logs to the correct location.

### Version Compatibility

This chart requires Kubernetes 1.25+ and Helm 3.7+ for full compatibility with kube-prometheus-stack and dashboard features.

The chart comes with dependencies that can install Grafana, Prometheus and Loki to the cluster to provide access to log, metrics and dashboards.
These may require further configuration for your cluster's storage capabilities. You can bring your own monitoring and logging if you prefer.

Setting `monitoring.enabled: true` installs [kube-prometheus-stack](https://github.com/grafana-community/helm-charts/tree/main/charts/grafana) as a subchart. If you chose to install this way, we recommend the following config to get metrics quickly. Please note that it requires 10Gi of storage minimum, and **does not have back ups enabled**. If you chose to install in this method we **highly** recommend configuring back ups to avoid loss of data.

Please modify this config with your chosen ingress and storage solutions. For ease of use please refer to the following terraform for the iam role to use with grafana and redis credentials.

- [Cloudwatch IAM role](https://github.com/ad-signalio/terraform-utils/blob/main/aws/tf-hosted-modules/tf-dt-iam-roles)
- [Redis Credentials AWS Secret](https://github.com/ad-signalio/terraform-utils/blob/main/aws/tf-hosted-modules/tf-dt-elasticache-redis)

```
monitoring:
  enabled: true
  awsDashboards:
    enabled: true
    cloudwatch:
      ## if you followed the reference architecture
      ## terraform the iam role pattern will be
      assumeRoleArn: arn:aws:iam::$YOUR_AWS_ACCOUNT_NUMBER_HERE$:role/$YOUR_CLUSTER_NAME_HERE-grafana-cloudwatch
      defaultRegion: us-east-1
  postgresDashboards:
    enabled: true
  kube-prometheus-stack:
    fullnameOverride: $YOUR_CLUSTER_NAME_HERE-kube-prometheus-stack
    crds:
      upgradeJob:
        enabled: true
        forceConflicts: true
    grafana:
      namespaceOverride: "match"
      enabled: true
      adminUser: admin
      admin:
        existingSecret: null
        userKey: null
        passwordKey: null
      serviceAccount:
        create: false
        name: adsignal-match
      ingress:
        enabled: true
        ingressClassName: $YOUR_INGRESS_CLASS_NAME_HERE
        annotations:
          $YOUR_INGRESS_ANNOTATIONS_HERE
        hosts:
          - $YOUR_INGRESS_HOSTNAME_HERE
        paths:
          - /*
      extraSecretMounts:
        - name: pg-secrets
          ## if you followed the reference architecture
          ## terraform the secret name is
          ## $YOUR_CLUSTER_NAME_HERE-rds-pg
          secretName: $YOUR_SECRET_NAME_HERE
          mountPath: /etc/secrets
          readOnly: true
          items:
            - key: username
              path: username
            - key: password
              path: password
            - key: db_name
              path: db_name
            - key: host
              path: host
            - key: port
              path: port
      ## if using loki for logging
      additionalDataSources:
        - name: Loki
          type: loki
          url: $YOUR_LOKI_URL_HERE
      persistence:
        type: pvc
        enabled: true
        storageClassName: gp2
        accessModes:
          - ReadWriteOnce
        size: 10Gi
    prometheus:
      service:
        enabled: true
        type: ClusterIP
        port: 9090
        targetPort: 9090
      prometheusSpec:
        ## scrape PodMonitors and ServiceMonitors
        ## from all namespaces with any labels
        podMonitorSelector: {}
        podMonitorSelectorNilUsesHelmValues: false
        podMonitorNamespaceSelector: {}
        serviceMonitorSelector: {}
        serviceMonitorSelectorNilUsesHelmValues: false
        serviceMonitorNamespaceSelector: {}
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: gp2
              resources:
                requests:
                  storage: 10Gi
    alertmanager:
      enabled: false
```

### Log Aggregation &  Alternatives

You *can* install loki-stack by enabling

```
monitoring:
  enabled: true
  logging:
    enabled: true
```

*However* this version of loki-stack is deprecated, and with no plan to move it to the `prometheus-community.github.io/helm-charts` repo, we recommend installing and maintaining your own loki deployment (or your log aggregation system of choice).

## Getting the most out of your metrics

We provide these dashboards:

1. Match Processing Pipeline Overview

This dashboard provides an overview of the Match processing pipeline in Kubernetes. It visualizes Sidekiq queue depths, OOM kills, CPU and memory usage, and throttling for different workload types (pods) in the "match" namespace. The dashboard uses Prometheus metrics and supports filtering by workload type. It helps operators monitor resource usage, queue health, and pod stability for Match workloads.

When `metrics` is enabled, Helm creates a Prometheus PodMonitor for each defined worker type. Prometheus then scrapes metrics from the worker pods in the defined namespace (default is "match" namespace).

Use this dashboard as a jumping point to discover any lags in processing.

Enable this with:
```yaml
monitoring:
  matchDashboards:
    enabled: true
```

2.  AWS RDS Dashboard

This is the [Grafana provided](https://grafana.com/grafana/dashboards/707-aws-rds/) AWS RDS dashboard. Here you can visualise key performance and health metrics for your Amazon RDS database.

Use this dashboard to quickly identify performance bottlenecks and resource saturation.

Enable this with:
```yaml
monitoring:
  awsDashboards:
    enabled: true
    cloudwatch:
      assumeRoleArn: arn:aws:iam::$YOUR_AWS_ACCOUNT_NUMBER_HERE$:role/$YOUR_CLUSTER_NAME_HERE-grafana-cloudwatch
      defaultRegion: $YOUR_REGION
```

3. Postgres Dashboard

The Postgres dashboard provides real-time visibility into your PostgreSQL database performance, including metrics like query throughput, cache hit rates, replication lag, and resource usage. It helps monitor database health, detect slow queries, and identify bottlenecks or abnormal behavior.

Use this dashboard to troubleshoot database issues, optimise performance, and ensure reliable operation of your Postgres instance.

Enable this with:
```yaml
monitoring:
  postgresDashboards:
    enabled: true
```

> Please consult with Ad-Signal technical services for monitoring configuration.

## Application Errors

The application is configured to send error traces to honeybadger.io.

> Please consult with Ad-Signal technical services for your unique API key.

### Honeybadger Configuration

Match uses Honeybadger for error tracking and monitoring. To configure Honeybadger, you need:

1. **Honeybadger API Key and Environment Name**: These will be provided to you by Ad-Signal technical services during setup.

2. **Create a Kubernetes secret** containing your API key:

```bash
kubectl create secret generic honeybadger-api-key \
  --namespace match \
  --from-literal=apiKey=YOUR_HONEYBADGER_API_KEY
```

3. **Configure your values file** with the environment name (required):

```yaml
honeybadger:
  secretName: honeybadger-api-key
  secretKey: apiKey
  environment: "your-environment-name"  # REQUIRED: Provided by Ad-Signal
```

> **Note**: The `environment` field is **required**. Helm will refuse to install the chart if this value is not set.

**If you need to use a different secret name or key**, update your values file accordingly:

```yaml
honeybadger:
  secretName: my-custom-honeybadger-secret  # Custom secret name
  secretKey: my-api-key                      # Custom key within the secret
  environment: "your-environment-name"       # REQUIRED: Provided by Ad-Signal
```

> We recommend using a secret management solution such as AWS Secrets Manager CSI Driver, External Secrets Operator, Vault, or another secret management solution of your choice.

## SMTP Email Configuration

Match can be configured to send email notifications via SMTP. To enable SMTP, we recommend creating a Kubernetes secret containing your SMTP credentials:

```bash
  kubectl create secret generic smtp-secrets \
    --from-literal=SMTP_ADDRESS=smtp.example.com \
    --from-literal=SMTP_DOMAIN=example.com \
    --from-literal=SMTP_PORT=587 \
    --from-literal=SMTP_USER_NAME='AKIABLAHBLAHBLAH' \
    --from-literal=SMTP_PASSWORD='awssecretaccesskeyhere' \
    --from-literal=MAILER_DEFAULT_FROM="no-reply@example.com"
```

The secret must include the following keys:
- `SMTP_ADDRESS`: SMTP server hostname (e.g. "smtp.example.com")
- `SMTP_DOMAIN`: HELO/EHLO domain to use (e.g. "example.com")
- `SMTP_PORT`: SMTP server port (e.g. "587")
- `SMTP_USER_NAME`: Username for SMTP authentication (Using AWS SES this will be the AWS Access Key ID for the smtp user)
- `SMTP_PASSWORD`: Password for SMTP authentication (Using AWS SES this will be AWS Secret Access Key for the smtp user)
- `MAILER_DEFAULT_FROM` : The default 'no-reply' address you wish to use. (e.g "no-reply@example.com")

Then enable SMTP in your values file:

```yaml
smtp:
  enabled: true
  secret:
    name: smtp-secrets
```

## Deploying with Argo

If the value `useArgoSyncWaveAnnotations` is set to `true`, the chart will use Argo Sync waves rather than helm hooks to configure ordering of data base migrations, service accounts and storage creation.

> **Important:** Secret generation is not supported when using Argo (`useArgoSyncWaveAnnotations=true`). Argo does not support Helm's `lookup()` function. Please set all secret generation flags to false (`secretKeys.secret.generate: false` and `owningUser.secret.generate: false`) and provide pre-created Kubernetes Secrets.

---

## Initial User Configuration

When Match is first deployed, an initial user account is created to allow you to access the system. This user is configured via the `owningUser` section in your values file.

```yaml
owningUser:
  email: "admin@example.invalid"
  firstName: "Admin"
  lastName: "User"
  organisationName: "Example Org"
```

**Configuration:**
- `email`: Email address for the initial user account (used for login)
- `firstName`: First name of the user
- `lastName`: Last name of the user
- `organisationName`: Name of the organization this user belongs to

> After the initial deployment, you should create additional user accounts through the Match web interface and can remove or disable this initial user account. Do not use this for production user management.

> The initial password for this user will be randomly generated during deployment. You can reset it through the Match web interface or using the Rails console. It is also possible to set a password in the values file.

## Sizing the Workloads

The folder `environment-sizes` contains a set of example size files for different environments. These can be used to size the workloads to your environment's needs. These roughly correlate with common cloud instance sizes (4xlarge, etc).

> Please consult with Ad-Signal technical services for sizing recommendations.

---

# AWS EKS QuickStart Deployment Guide

Deploying the chart with the default values will install Match to the `match` namespace, however, you will need to modify your own values.yml file to achieve a fully functional EKS deployment.

## Prerequisites (Reference Architecture users)

Complete these steps before installing this chart.

**1. Deploy the Terraform reference architecture**

Follow the two-stage apply in the reference architecture README. Once complete, update your kubeconfig:

```bash
aws eks update-kubeconfig --region <your-region> --name <your-cluster-name>
```

**2. Create the two manually-provisioned AWS Secrets Manager secrets**

These are not created by Terraform and must exist before installing the `secrets-configuration` chart:

```bash
# Honeybadger API key (provided to you by Snicket Labs)
aws secretsmanager create-secret \
  --name match-honeybadger-secret \
  --region <your-region> \
  --secret-string '{"apiKey":"<your-honeybadger-key>"}'

# Snicketlabs registry credentials (access token generated at https://deploy.snicketlabs.io/settings/access-tokens)
aws secretsmanager create-secret \
  --name match-docker-secret \
  --region <your-region> \
  --secret-string '{"auths":{"registry.snicketlabs.io":{"password":"<your-access-token>"}}}'
```

**3. Install the `secrets-configuration` chart**

This syncs all required Kubernetes secrets from AWS Secrets Manager into the cluster. Run from your infrastructure directory — all values come directly from Terraform outputs:

```bash
helm install secrets-configuration <path-to-reference-architecture>/optional-add-ons/secrets-configuration \
  -n match --create-namespace \
  --set clusterName=$(terraform output -json eks_cluster_details | jq -r '.cluster_name') \
  --set apiSecretName=$(terraform output -raw api_secret_name) \
  --set rdsPgSecretName=$(terraform output -raw rds_pg_secret_name) \
  --set userSecretName=$(terraform output -raw user_secret_name) \
  --set secretStoreRoleArn=$(terraform output -raw secret_store_role_arn) \
  --set redisSecretName=$(terraform output -raw redis_secret_name)
```

The secrets (`match-api-secrets`, `match-postgres-password`, `match-owning-user-credentials`, `honeybadger-api-key`) are synced from AWS Secrets Manager when the match pods first mount their CSI volumes — they will not appear in `kubectl get secrets` until after the chart is installed and pods start.

**4. Create the image pull secret**

See [Image Pull Secrets](#image-pull-secrets) below.

---

Use the steps below as a checklist when creating your own `your-custom-values.yaml` file.

## 1. Image Tags

The main `image.tag` defaults to the chart's `appVersion` if not set. Override it only when you need to pin the match app to a specific release independently of the chart. The fingerprinter image (`fingerprinter.image.tag`) must always be set explicitly as it releases on its own cadence.

```yaml
# image.tag is optional — omit to use the chart's appVersion
image:
  repository: registry.snicketlabs.io/snicketlabs/match
  # tag: 2.0.0  # uncomment to override appVersion

# fingerprinter.image.tag must be set explicitly
fingerprinter:
  image:
    repository: registry.snicketlabs.io/snicketlabs/match-fp
    tag: 2.0.0
```

> Don't forget to configure the initial user account. See the [Initial User Configuration](#initial-user-configuration) section above for details.

## 2. Initial User Configuration

```yaml
owningUser:
  email: "admin@{YOUR_DOMAIN}"
  firstName: "Admin"
  lastName: "User"
  organisationName: "{YOUR_ORGANISATION_NAME}"
```

---

## 3. AWS IAM Service Account (IRSA)

See reference architecture or configure IRSA for service account to access AWS resources such as S3.

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::*********:role/your-service-account-role
```

> The reference architecture contains sample IAM permissions required by the application.

---

## 4. Domain and Ingress Configuration

### Domain Name

Set your application domain.

```yaml
domain: your-domain-name.example.com # Your domain name
```

### Ingress Configuration

Match is intended to run on a dedicated cluster. Configure ingress for EKS Auto Mode — the built-in ALB controller does not honour `alb.ingress.kubernetes.io/load-balancer-attributes`, so the idle timeout is set via `ingressClassParams` instead.

```yaml
ingress:
  enabled: true
  className: "match-alb"
  annotations:
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: {YOUR_CERTIFICATE_ARN}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /up
    alb.ingress.kubernetes.io/success-codes: "200-402"
    external-dns.alpha.kubernetes.io/hostname: {YOUR_DOMAIN}

  # Match performs long-running comparison requests. The ALB default idle
  # timeout of 60s may cause 504 timeout errors on these requests. On EKS Auto Mode
  # this must be set via IngressClassParams rather than an annotation.
  ingressClassParams:
    create: true
    scheme: internet-facing
    loadBalancerAttributes:
      - key: idle_timeout.timeout_seconds
        value: "300"

  hosts:
    - host: {YOUR_DOMAIN}
      paths:
        - path: /
          pathType: Prefix
```

## 5. Database and Redis Configuration

### PostgreSQL (RDS)

> See the reference architecture for AWS RDS and ElastiCache configuration.

This chart expects the database password to exist as a Kubernetes secret before install. There are two ways to provide it:

**Option A — AWS Secrets Manager via ASCP (recommended for reference architecture users)**

If you are using the [match-reference-architecture](https://github.com/ad-signalio/match-reference-architecture) Terraform, the RDS password is automatically stored in AWS Secrets Manager. Install the `secrets-configuration` chart from `optional-add-ons/secrets-configuration` in the reference architecture repo to sync it (and all other required secrets) into the cluster via the AWS Secrets Store CSI Driver:

```bash
helm install secrets-configuration ./optional-add-ons/secrets-configuration -n match -f your-values.yaml
```

This chart is what creates `match-postgres-password`, `match-api-secrets`, `match-owning-user-credentials`, and `honeybadger-api-key` as Kubernetes secrets. Without it (or equivalent manual steps below), the match pods will fail to start with `CreateContainerConfigError`.

**Option B — Manual secret creation**

If you are not using ASCP, create the required secrets manually:

```bash
kubectl create secret generic match-postgres-password \
  --namespace match \
  --from-literal=password='YOUR_DATABASE_PASSWORD'
```

See also the `secretKeys` section of `values.yaml` for `match-api-secrets` and other required secrets — all must exist before installing this chart.

**Configure the connection:**

```yaml
postgres:
  enabled: false  # Keep false when using external RDS
  database: match
  username: match
  primaryHost: my-external-database.example.internal
  port: 5432
  passwordSecret:
    name: match-postgres-password
    key: password
```

### Redis (ElastiCache)

Configure connection to your external ElastiCache Redis cluster:

```yaml
redis:
  enabled: false  # Keep false when using external ElastiCache

sidekiq:
  redisServerUrl: "rediss://your-elasticache-endpoint:6379/0"
  redisClientUrl: "rediss://your-elasticache-endpoint:6379/0"
```

### 6. S3 Storage Configuration

#### AWS S3 (IRSA)

Create a primary S3 bucket for the application.

> Consult the reference architecture for AWS S3 configuration.

Configure your primary S3 bucket in the values file:

```yaml
s3:
  primaryBucket: your-s3-bucket-name  # Your S3 bucket name
  region: us-east-1                   # Your AWS region
```

> Ensure your IAM role (IRSA) has appropriate S3 permissions for the bucket.

#### S3-Compatible Storage (Non-AWS)

For Ceph, MinIO, GCS S3-interop, or any other S3-compatible store, see [S3-Compatible Primary Storage (Non-AWS)](#s3-compatible-primary-storage-non-aws) in the requirements section above.

## 7. Image Pull Secrets

For configuring image pull secrets to authenticate with the Snicket Labs (formerly Ad Signal) container registry, see the [Image Pull Secrets](README.md#image-pull-secrets) section in the main README.

## 8. Add HoneyBadger Credentials

See the [Honeybadger Configuration](README#honeybadger-configuration) section.

## 9. Configure the chart to use the EFS shared storage

If you are using the Match reference AWS implementation you will need to configure shared storage:

```
storage:
  sharedStorage:
    storageClassName: match-shared-storage
```

## 10. Network Access Requirements

| Direction | Service | Address(s) | Port | Description |
|-----------|---------|------------|------|-------------|
| Egress | Honeybadger | api.honeybadger.io | 443 | Application Error tracking [Honeybadger API IP addresses](https://docs.honeybadger.io/resources/security/#for-exception-monitoring)|
| Egress | Snicketlabs Registry | registry.snicketlabs.io | 443 | Container images and Helm chart |
| Egress | SMTP | Customers SMTP server | - | For password resets etc. |
| Ingress | Web/API | Customer domain | 443 | Access to Web interface and API |

---

## Quick Start Checklist

### Pre-install (Reference Architecture users)

- [ ] Terraform reference architecture deployed (two-stage apply complete)
- [ ] kubeconfig updated (`aws eks update-kubeconfig`)
- [ ] `match-honeybadger-secret` created in AWS Secrets Manager
- [ ] `match-docker-secret` created in AWS Secrets Manager
- [ ] `secrets-configuration` chart installed (syncs k8s secrets from AWS Secrets Manager)
- [ ] `matchcredentials` image pull secret created in the `match` namespace

### Values configuration

- [ ] Fingerprinter image tag set (`fingerprinter.image.tag`) — match app defaults to chart `appVersion`
- [ ] Initial user configured (`owningUser.email`, `owningUser.organisationName`)
- [ ] IRSA service account annotation set
- [ ] Domain name configured
- [ ] Ingress configured with ACM certificate ARN
- [ ] Postgres connection configured (use Terraform outputs)
- [ ] Redis connection configured (use Terraform outputs)
- [ ] S3 bucket configured (use Terraform outputs)
- [ ] EFS shared storage class set (`storageClassName: match-shared-storage`)
- [ ] `imagePullSecrets` set to `matchcredentials` in values

---

## Deployment Command

Once you've customized your `values.yaml` file, install the chart with the relevant size file:

> Please consult with Snicketlabs technical services for sizing recommendations.

Charts are served directly from the Snicketlabs OCI registry. Ensure you are logged in first (see [Image Pull Secrets](#image-pull-secrets)), then install:

```bash
helm install oci://registry.snicketlabs.io/snicketlabs/helm-match/adsignal-match \
  --version <chart-version> \
  --namespace match \
  --generate-name \
  --create-namespace \
  --values your-custom-values.yaml -f environment-sizes/{SIZE}.yaml
```

> **Note**: The multiple `-f` flags apply values files in order using Helm's deep merge. The environment size file (e.g., `environment-sizes/small/small.yaml`) overrides only the `maxReplicaCount` scaling limits from `values.yaml`. All other configurations (resources, queues, timeouts) are preserved from the base values. See [Values File Merging](#values-file-merging) for details.

### Retrieving the Initial Password

The helm command above will output the kubectl command to retrieve the initial user password, if you are unable to use this (Argo, Flux, etc.) you can use the kubectl command below:

```bash
kubectl get secret match-owning-user-credentials -n match -o jsonpath='{.data.password}' | base64 -d
```

### Resetting the Initial Password

The initial user's email is set via `owningUser.email` in your helm values. To reset the password from the command line, use the Rails runner on the web pod:

```bash
kubectl exec -n match deployment/web-adsignal-match -- bin/rails runner \
  "u = User.find_by(email: 'admin@yourcompany.com'); \
   new_pass = 'YourNewPassword123!'; \
   u.update!(password: new_pass, password_confirmation: new_pass); \
   puts 'Password reset for ' + u.email"
```

To sync the password back to the value in the Kubernetes secret (e.g. after rotating in AWS Secrets Manager):

```bash
NEW_PASS=$(kubectl get secret match-owning-user-credentials -n match -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n match deployment/web-adsignal-match -- bin/rails runner \
  "u = User.find_by(email: 'admin@yourcompany.com'); \
   u.update!(password: '$NEW_PASS', password_confirmation: '$NEW_PASS'); \
   puts 'Password reset for ' + u.email"
```

----

## Getting Help

> For sizing recommendations, production configuration guidance, or deployment assistance, please consult with Snicket Labs technical services.

**Common Issues:**
- **Image pull errors**: Verify `imagePullSecrets` are correctly configured and that image tags are valid
- **Database connection issues**: Check RDS security groups and secret values
- **Storage issues**: Ensure your storage class supports ReadWriteMany
- **Ingress issues**: Verify ALB controller is installed and certificate ARN is correct

## Long Term Checklist

Use this checklist to ensure you've replaced more temporary measures with production-ready solutions.

> For secrets management, you can use AWS Secrets Manager CSI Driver or another Kubernetes secret management solution of your choice.

- [ ] Replaced `imagePullSecrets` with a secret manager
- [ ] Migrated database password from manual Kubernetes secret to a secret manager
- [ ] Configured Redis credentials using a secret manager instead of direct URLs
- [ ] Configured SMTP using a secret manager
- [ ] Set up monitoring and alerting (Prometheus, Grafana, Loki) # Please consult with Snicket Labs technical services for production-ready solutions
- [ ] Configured database backups and disaster recovery procedures
- [ ] Reviewed and optimized resource requests and limits based on actual usage

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://grafana.github.io/helm-charts | loki-stack | 2.10.2 |
| https://prometheus-community.github.io/helm-charts | kube-prometheus-stack | 78.4.0 |
| oci://registry-1.docker.io/cloudpirates | postgres | 0.5.0 |
| oci://registry-1.docker.io/cloudpirates | redis | 0.3.3 |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Snicket Labs Match | <platform@snicketlabs.io> |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| adminUser.email | string | `"admin@snicketlabs.io"` |  |
| adminUser.firstName | string | `"Admin"` |  |
| adminUser.lastName | string | `"User"` |  |
| adminUser.organisationName | string | `"Snicket Labs"` |  |
| adminUser.organisationRoles | string | `"assure_admin"` |  |
| adminUser.roles | string | `"email_and_password,assure_admin"` |  |
| affinity | object | `{}` |  |
| contentSecrets | list | `[]` |  |
| dbPrepareJob.annotations | object | `{}` |  |
| dbPrepareJob.argoSyncWaveAnnotations."argocd.argoproj.io/hook" | string | `"PostSync"` |  |
| dbPrepareJob.argoSyncWaveAnnotations."argocd.argoproj.io/hook-delete-policy" | string | `"HookSucceeded"` |  |
| dbPrepareJob.argoSyncWaveAnnotations."argocd.argoproj.io/sync-wave" | string | `"0"` |  |
| dbPrepareJob.helmHookAnnotations."helm.sh/hook" | string | `"post-install,pre-upgrade"` |  |
| dbPrepareJob.helmHookAnnotations."helm.sh/hook-delete-policy" | string | `"before-hook-creation,hook-succeeded"` |  |
| dbPrepareJob.helmHookAnnotations."helm.sh/hook-weight" | string | `"0"` |  |
| dbSeedJob.annotations | object | `{}` |  |
| dbSeedJob.argoSyncWaveAnnotations."argocd.argoproj.io/hook" | string | `"PostSync"` |  |
| dbSeedJob.argoSyncWaveAnnotations."argocd.argoproj.io/hook-delete-policy" | string | `"HookSucceeded"` |  |
| dbSeedJob.argoSyncWaveAnnotations."argocd.argoproj.io/sync-wave" | string | `"1"` |  |
| dbSeedJob.helmHookAnnotations."helm.sh/hook" | string | `"post-install,post-upgrade"` |  |
| dbSeedJob.helmHookAnnotations."helm.sh/hook-delete-policy" | string | `"before-hook-creation,hook-succeeded"` |  |
| dbSeedJob.helmHookAnnotations."helm.sh/hook-weight" | string | `"1"` |  |
| domain | string | `"match-instance.example.com"` |  |
| duration_async_required | string | `"300"` |  |
| env | list | `[]` |  |
| extraEnvSecrets | list | `[]` |  |
| extraEnvs | list | `[]` |  |
| fingerPrinterDebug | bool | `false` |  |
| fingerprinter.image.repository | string | `"adsignal/match-fp"` |  |
| fingerprinter.image.tag | string | `"2.0.1"` |  |
| fullnameOverride | string | `"adsignal-match"` |  |
| gke.enabled | bool | `false` |  |
| gke.healthCheckPath | string | `"/up"` |  |
| global.redis.password | string | `""` |  |
| honeybadger.environment | string | `""` |  |
| honeybadger.secretKey | string | `"apiKey"` |  |
| honeybadger.secretName | string | `"honeybadger-api-key"` |  |
| httpRoute.annotations | object | `{}` |  |
| httpRoute.enabled | bool | `false` |  |
| httpRoute.hostnames | list | `[]` |  |
| httpRoute.parentRefs[0].name | string | `"match-gateway"` |  |
| httpRoute.rules[0].matches[0].path.type | string | `"PathPrefix"` |  |
| httpRoute.rules[0].matches[0].path.value | string | `"/"` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"adsignal/match"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"chart-example.local"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.ingressClassParams.create | bool | `false` |  |
| ingress.ingressClassParams.loadBalancerAttributes | list | `[]` |  |
| ingress.ingressClassParams.scheme | string | `"internet-facing"` |  |
| ingress.tls | list | `[]` |  |
| kedaAutoScaling.enabled | bool | `false` |  |
| kedaAutoScaling.redis.authenticationRef.enabled | bool | `false` |  |
| kedaAutoScaling.redis.authenticationRef.name | string | `"keda-trigger-auth-redis"` |  |
| kedaAutoScaling.redis.databaseIndex | int | `0` |  |
| kedaAutoScaling.redis.enabledTLS | bool | `true` |  |
| kedaAutoScaling.redis.pollingInterval | int | `10` |  |
| kedaAutoScaling.redis.port | int | `6379` |  |
| kedaAutoScaling.terminationGracePeriodSeconds | int | `30` |  |
| logLevel | string | `"info"` |  |
| log_path | string | `"/app/log/production.log"` |  |
| log_path_mode | string | `"0664"` |  |
| materialProcessingCount | string | `"default=5"` |  |
| materialProcessingPipelines | string | `"default|duration>=0"` |  |
| metrics.enabled | bool | `true` |  |
| metrics.metricsPort | int | `9090` |  |
| monitoring.enabled | bool | `false` |  |
| monitoring.matchDashboards.enabled | bool | `false` |  |
| nameOverride | string | `"adsignal-match"` |  |
| nodeSelector | object | `{}` |  |
| owningUser.email | string | `"admin@example.invalid"` |  |
| owningUser.firstName | string | `"Admin"` |  |
| owningUser.lastName | string | `"User"` |  |
| owningUser.organisationName | string | `"Example Org"` |  |
| owningUser.secret.generate | bool | `false` |  |
| owningUser.secret.name | string | `"match-owning-user-credentials"` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext.fsGroup | int | `65532` |  |
| podSecurityContext.runAsUser | int | `65532` |  |
| postgres.auth.database | string | `"match"` |  |
| postgres.auth.username | string | `"matchdb"` |  |
| postgres.enabled | bool | `false` |  |
| postgres.fullnameOverride | string | `"match-postgres"` |  |
| postgres.primary.resources.limits.cpu | string | `"500m"` |  |
| postgres.primary.resources.limits.memory | string | `"512Mi"` |  |
| postgres.primary.resources.requests.cpu | string | `"100m"` |  |
| postgres.primary.resources.requests.memory | string | `"256Mi"` |  |
| railsConsole.enabled | bool | `false` |  |
| railsConsole.replicas | int | `1` |  |
| railsConsole.resources.limits.memory | string | `"1Gi"` |  |
| railsConsole.resources.requests.cpu | string | `"50m"` |  |
| railsConsole.resources.requests.memory | string | `"512Mi"` |  |
| rails_env | string | `"production"` |  |
| redis.auth.enabled | bool | `false` |  |
| redis.enabled | bool | `false` |  |
| redis.master.resources.limits.cpu | string | `"200m"` |  |
| redis.master.resources.limits.memory | string | `"256Mi"` |  |
| redis.master.resources.requests.cpu | string | `"100m"` |  |
| redis.master.resources.requests.memory | string | `"128Mi"` |  |
| redis.port | int | `6379` |  |
| redis.replica.resources.limits.cpu | string | `"200m"` |  |
| redis.replica.resources.limits.memory | string | `"256Mi"` |  |
| redis.replica.resources.requests.cpu | string | `"100m"` |  |
| redis.replica.resources.requests.memory | string | `"128Mi"` |  |
| redis.useSentinel | bool | `false` |  |
| s3.accessKeyId | string | `"dummy-key"` |  |
| s3.credentialsSecret | string | `""` |  |
| s3.endpoint | string | `""` |  |
| s3.primaryBucket | string | `"adsignal-primary-bucket"` |  |
| s3.region | string | `"us-east-1"` |  |
| s3.secretAccessKey | string | `"dummy-secret"` |  |
| scaledJobs.audiomatch-fingerprint.activeDeadlineSeconds | int | `28800` |  |
| scaledJobs.audiomatch-fingerprint.enabled | bool | `true` |  |
| scaledJobs.audiomatch-fingerprint.maxReplicaCount | int | `5` |  |
| scaledJobs.audiomatch-fingerprint.resources.limits.cpu | string | `"1.5"` |  |
| scaledJobs.audiomatch-fingerprint.resources.limits.memory | string | `"8Gi"` |  |
| scaledJobs.audiomatch-fingerprint.resources.requests.cpu | string | `"1"` |  |
| scaledJobs.audiomatch-fingerprint.resources.requests.memory | string | `"5500Mi"` |  |
| scaledJobs.audiomatch-fingerprint.sideKiqQueue | string | `"audio_match_frames_fingerprint_tasks"` |  |
| scaledJobs.compare-relate.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.compare-relate.enabled | bool | `true` |  |
| scaledJobs.compare-relate.maxReplicaCount | int | `5` |  |
| scaledJobs.compare-relate.resources.limits.cpu | string | `"0.5"` |  |
| scaledJobs.compare-relate.resources.limits.memory | string | `"1Gi"` |  |
| scaledJobs.compare-relate.resources.requests.cpu | string | `"0.5"` |  |
| scaledJobs.compare-relate.resources.requests.memory | string | `"1Gi"` |  |
| scaledJobs.compare-relate.sideKiqQueue | string | `"relate_materials"` |  |
| scaledJobs.comparison-longform-data-generation.activeDeadlineSeconds | int | `6600` |  |
| scaledJobs.comparison-longform-data-generation.enabled | bool | `true` |  |
| scaledJobs.comparison-longform-data-generation.maxReplicaCount | int | `6` |  |
| scaledJobs.comparison-longform-data-generation.resources.limits.memory | string | `"3Gi"` |  |
| scaledJobs.comparison-longform-data-generation.resources.requests.cpu | int | `1` |  |
| scaledJobs.comparison-longform-data-generation.resources.requests.memory | string | `"3Gi"` |  |
| scaledJobs.comparison-longform-data-generation.sideKiqQueue | string | `"generate_grouped_comparison_result_data"` |  |
| scaledJobs.fingerprinter-audio.activeDeadlineSeconds | int | `3600` |  |
| scaledJobs.fingerprinter-audio.enabled | bool | `true` |  |
| scaledJobs.fingerprinter-audio.fingerprinter.resources.limits.cpu | string | `"4.5"` |  |
| scaledJobs.fingerprinter-audio.fingerprinter.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.fingerprinter-audio.fingerprinter.resources.requests.cpu | string | `"4.5"` |  |
| scaledJobs.fingerprinter-audio.fingerprinter.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.fingerprinter-audio.maxReplicaCount | int | `2` |  |
| scaledJobs.fingerprinter-audio.resources.limits.cpu | string | `"1500m"` |  |
| scaledJobs.fingerprinter-audio.resources.limits.memory | string | `"2.5Gi"` |  |
| scaledJobs.fingerprinter-audio.resources.requests.cpu | string | `"1500m"` |  |
| scaledJobs.fingerprinter-audio.resources.requests.memory | string | `"2.5Gi"` |  |
| scaledJobs.fingerprinter-audio.sideKiqQueue | string | `"native_audio_processing_tasks"` |  |
| scaledJobs.fingerprinter-video.activeDeadlineSeconds | int | `14400` |  |
| scaledJobs.fingerprinter-video.enabled | bool | `true` |  |
| scaledJobs.fingerprinter-video.fingerprinter.resources.limits.cpu | string | `"5"` |  |
| scaledJobs.fingerprinter-video.fingerprinter.resources.limits.memory | string | `"4Gi"` |  |
| scaledJobs.fingerprinter-video.fingerprinter.resources.requests.cpu | string | `"3.5"` |  |
| scaledJobs.fingerprinter-video.fingerprinter.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.fingerprinter-video.maxReplicaCount | int | `2` |  |
| scaledJobs.fingerprinter-video.resources.limits.cpu | string | `"500m"` |  |
| scaledJobs.fingerprinter-video.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.fingerprinter-video.resources.requests.cpu | string | `"200m"` |  |
| scaledJobs.fingerprinter-video.resources.requests.memory | string | `"850Mi"` |  |
| scaledJobs.fingerprinter-video.sideKiqQueue | string | `"video_match_frames_native_fingerprint_tasks"` |  |
| scaledJobs.ingest-attach-image.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.ingest-attach-image.enabled | bool | `true` |  |
| scaledJobs.ingest-attach-image.maxReplicaCount | int | `5` |  |
| scaledJobs.ingest-attach-image.resources.limits.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-attach-image.resources.limits.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-attach-image.resources.requests.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-attach-image.resources.requests.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-attach-image.sideKiqQueue | string | `"video_match_frames_attach_image_tasks"` |  |
| scaledJobs.ingest-download-media.activeDeadlineSeconds | int | `5400` |  |
| scaledJobs.ingest-download-media.enabled | bool | `true` |  |
| scaledJobs.ingest-download-media.maxReplicaCount | int | `5` |  |
| scaledJobs.ingest-download-media.resources.limits.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-download-media.resources.limits.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-download-media.resources.requests.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-download-media.resources.requests.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-download-media.sideKiqQueue | string | `"download_media"` |  |
| scaledJobs.ingest-materials.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.ingest-materials.enabled | bool | `true` |  |
| scaledJobs.ingest-materials.maxReplicaCount | int | `5` |  |
| scaledJobs.ingest-materials.resources.limits.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-materials.resources.limits.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-materials.resources.requests.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-materials.resources.requests.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-materials.sideKiqQueue | string | `"ingest_materials"` |  |
| scaledJobs.ingest-process-materials.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.ingest-process-materials.enabled | bool | `true` |  |
| scaledJobs.ingest-process-materials.maxReplicaCount | int | `5` |  |
| scaledJobs.ingest-process-materials.resources.limits.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-process-materials.resources.limits.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-process-materials.resources.requests.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-process-materials.resources.requests.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-process-materials.sideKiqQueue | string | `"process_materials"` |  |
| scaledJobs.ingest-process-media.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.ingest-process-media.enabled | bool | `true` |  |
| scaledJobs.ingest-process-media.maxReplicaCount | int | `5` |  |
| scaledJobs.ingest-process-media.resources.limits.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-process-media.resources.limits.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-process-media.resources.requests.cpu | string | `"0.5"` |  |
| scaledJobs.ingest-process-media.resources.requests.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-process-media.sideKiqQueue | string | `"process_media"` |  |
| scaledJobs.ingest-process-qc.activeDeadlineSeconds | int | `3600` |  |
| scaledJobs.ingest-process-qc.enabled | bool | `true` |  |
| scaledJobs.ingest-process-qc.maxReplicaCount | int | `2` |  |
| scaledJobs.ingest-process-qc.resources.limits.cpu | string | `"4.0"` |  |
| scaledJobs.ingest-process-qc.resources.limits.memory | string | `"3Gi"` |  |
| scaledJobs.ingest-process-qc.resources.requests.cpu | string | `"2.0"` |  |
| scaledJobs.ingest-process-qc.resources.requests.memory | string | `"0.8Gi"` |  |
| scaledJobs.ingest-process-qc.sideKiqQueue | string | `"process_qc"` |  |
| scaledJobs.ingest-proxy-generate.activeDeadlineSeconds | int | `5400` |  |
| scaledJobs.ingest-proxy-generate.enabled | bool | `true` |  |
| scaledJobs.ingest-proxy-generate.maxReplicaCount | int | `5` |  |
| scaledJobs.ingest-proxy-generate.resources.limits.cpu | string | `"6"` |  |
| scaledJobs.ingest-proxy-generate.resources.limits.memory | string | `"4Gi"` |  |
| scaledJobs.ingest-proxy-generate.resources.requests.cpu | string | `"2"` |  |
| scaledJobs.ingest-proxy-generate.resources.requests.memory | string | `"1.25Gi"` |  |
| scaledJobs.ingest-proxy-generate.sideKiqQueue | string | `"proxy_generate_tasks"` |  |
| scaledJobs.process-ai-tagging.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-ai-tagging.enabled | bool | `true` |  |
| scaledJobs.process-ai-tagging.maxReplicaCount | int | `5` |  |
| scaledJobs.process-ai-tagging.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-ai-tagging.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-ai-tagging.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-ai-tagging.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-ai-tagging.sideKiqQueue | string | `"ai_tagging"` |  |
| scaledJobs.process-audio-insights.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-audio-insights.enabled | bool | `true` |  |
| scaledJobs.process-audio-insights.maxReplicaCount | int | `5` |  |
| scaledJobs.process-audio-insights.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-audio-insights.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-audio-insights.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-audio-insights.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-audio-insights.sideKiqQueue | string | `"audio_insights"` |  |
| scaledJobs.process-compare-results.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-compare-results.enabled | bool | `true` |  |
| scaledJobs.process-compare-results.maxReplicaCount | int | `5` |  |
| scaledJobs.process-compare-results.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-compare-results.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-compare-results.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-compare-results.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-compare-results.sideKiqQueue | string | `"compare_materials_results"` |  |
| scaledJobs.process-complete-materials.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-complete-materials.enabled | bool | `true` |  |
| scaledJobs.process-complete-materials.maxReplicaCount | int | `5` |  |
| scaledJobs.process-complete-materials.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-complete-materials.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-complete-materials.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-complete-materials.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-complete-materials.sideKiqQueue | string | `"complete_materials"` |  |
| scaledJobs.process-extract-frames.activeDeadlineSeconds | int | `5400` |  |
| scaledJobs.process-extract-frames.enabled | bool | `true` |  |
| scaledJobs.process-extract-frames.maxReplicaCount | int | `5` |  |
| scaledJobs.process-extract-frames.resources.limits.cpu | string | `"3"` |  |
| scaledJobs.process-extract-frames.resources.limits.memory | string | `"1500Mi"` |  |
| scaledJobs.process-extract-frames.resources.requests.cpu | string | `"1"` |  |
| scaledJobs.process-extract-frames.resources.requests.memory | string | `"512Mi"` |  |
| scaledJobs.process-extract-frames.sideKiqQueue | string | `"video_match_frames_extract_frames_tasks"` |  |
| scaledJobs.process-extract.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-extract.enabled | bool | `true` |  |
| scaledJobs.process-extract.maxReplicaCount | int | `5` |  |
| scaledJobs.process-extract.resources.limits.cpu | string | `"2"` |  |
| scaledJobs.process-extract.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-extract.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-extract.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-extract.sideKiqQueue | string | `"video_match_frames_extract_tasks"` |  |
| scaledJobs.process-frames.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-frames.enabled | bool | `true` |  |
| scaledJobs.process-frames.maxReplicaCount | int | `5` |  |
| scaledJobs.process-frames.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-frames.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-frames.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-frames.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-frames.sideKiqQueue | string | `"process_frames"` |  |
| scaledJobs.process-ingest-frames.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-ingest-frames.enabled | bool | `true` |  |
| scaledJobs.process-ingest-frames.maxReplicaCount | int | `5` |  |
| scaledJobs.process-ingest-frames.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-ingest-frames.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-ingest-frames.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-ingest-frames.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-ingest-frames.sideKiqQueue | string | `"ingest_frames"` |  |
| scaledJobs.process-sbf.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-sbf.enabled | bool | `true` |  |
| scaledJobs.process-sbf.maxReplicaCount | int | `5` |  |
| scaledJobs.process-sbf.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-sbf.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-sbf.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-sbf.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-sbf.sideKiqQueue | string | `"process_sbf"` |  |
| scaledJobs.process-unique-frames-create.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-unique-frames-create.enabled | bool | `true` |  |
| scaledJobs.process-unique-frames-create.maxReplicaCount | int | `5` |  |
| scaledJobs.process-unique-frames-create.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-unique-frames-create.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-unique-frames-create.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-unique-frames-create.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-unique-frames-create.sideKiqQueue | string | `"video_unique_frames_create_tasks"` |  |
| scaledJobs.process-unique-frames-groups.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-unique-frames-groups.enabled | bool | `true` |  |
| scaledJobs.process-unique-frames-groups.maxReplicaCount | int | `5` |  |
| scaledJobs.process-unique-frames-groups.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-unique-frames-groups.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-unique-frames-groups.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-unique-frames-groups.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-unique-frames-groups.sideKiqQueue | string | `"video_unique_frames_create_groups_tasks"` |  |
| scaledJobs.process-video-fingerprint.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-video-fingerprint.enabled | bool | `true` |  |
| scaledJobs.process-video-fingerprint.maxReplicaCount | int | `5` |  |
| scaledJobs.process-video-fingerprint.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-video-fingerprint.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-video-fingerprint.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-video-fingerprint.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-video-fingerprint.sideKiqQueue | string | `"video_match_frames_fingerprint_tasks"` |  |
| scaledJobs.process-whole-media-compare.activeDeadlineSeconds | int | `600` |  |
| scaledJobs.process-whole-media-compare.enabled | bool | `true` |  |
| scaledJobs.process-whole-media-compare.maxReplicaCount | int | `5` |  |
| scaledJobs.process-whole-media-compare.resources.limits.cpu | string | `"0.75"` |  |
| scaledJobs.process-whole-media-compare.resources.limits.memory | string | `"2Gi"` |  |
| scaledJobs.process-whole-media-compare.resources.requests.cpu | string | `"0.75"` |  |
| scaledJobs.process-whole-media-compare.resources.requests.memory | string | `"2Gi"` |  |
| scaledJobs.process-whole-media-compare.sideKiqQueue | string | `"video_whole_media_compare_tasks"` |  |
| scaledObjects.generic.dbFollowerPoolSize | int | `10` |  |
| scaledObjects.generic.dbPoolSize | int | `10` |  |
| scaledObjects.generic.maxReplicaCount | int | `3` |  |
| scaledObjects.generic.minReplicaCount | int | `1` |  |
| scaledObjects.generic.queues[0].name | string | `"default"` |  |
| scaledObjects.generic.queues[0].priority | int | `1` |  |
| scaledObjects.generic.queues[1].name | string | `"pipeline"` |  |
| scaledObjects.generic.queues[1].priority | int | `2` |  |
| scaledObjects.generic.queues[2].name | string | `"mailers"` |  |
| scaledObjects.generic.queues[2].priority | int | `3` |  |
| scaledObjects.generic.queues[3].name | string | `"active_storage_purge"` |  |
| scaledObjects.generic.queues[3].priority | int | `4` |  |
| scaledObjects.generic.queues[4].name | string | `"refresh_ingest_source_reports"` |  |
| scaledObjects.generic.queues[4].priority | int | `5` |  |
| scaledObjects.generic.resources.limits.cpu | string | `"300m"` |  |
| scaledObjects.generic.resources.limits.memory | string | `"1500Mi"` |  |
| scaledObjects.generic.resources.requests.cpu | string | `"300m"` |  |
| scaledObjects.generic.resources.requests.memory | string | `"300Mi"` |  |
| scaledObjects.generic.sidekiqConcurrency | int | `10` |  |
| scaledObjects.generic.sidekiqTimeout | int | `30` |  |
| secretKeys.secret.generate | bool | `false` |  |
| secretKeys.secret.name | string | `"match-api-secrets"` |  |
| securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| securityContext.readOnlyRootFilesystem | bool | `true` |  |
| securityContext.runAsUser | int | `65532` |  |
| service.port | int | `3000` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.argoSyncWaveAnnotations."argocd.argoproj.io/sync-wave" | string | `"-2"` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.helmHookAnnotations."helm.sh/hook" | string | `"pre-install,pre-upgrade"` |  |
| serviceAccount.helmHookAnnotations."helm.sh/hook-weight" | string | `"-2"` |  |
| serviceAccount.name | string | `""` |  |
| sidekiq.redisClientUrl | string | `"redis://match-redis:6379/0"` |  |
| sidekiq.redisServerUrl | string | `"redis://match-redis:6379/0"` |  |
| smtp.enabled | bool | `false` |  |
| smtp.secret.name | string | `"smtp-secrets"` |  |
| storage.local.createLocalStorageClass | bool | `false` |  |
| storage.local.enabled | bool | `false` |  |
| storage.sharedStorage.annotations | object | `{}` |  |
| storage.sharedStorage.argoSyncWaveAnnotations."argocd.argoproj.io/sync-wave" | string | `"-1"` |  |
| storage.sharedStorage.claimName | string | `"match-shared-storage"` |  |
| storage.sharedStorage.enabled | bool | `true` |  |
| storage.sharedStorage.size | string | `"100Gi"` |  |
| storage.sharedStorage.storageClassName | string | `""` |  |
| storage.tmpStorage.enabled | bool | `true` |  |
| storage.tmpStorage.path | string | `"/tmp/app_tmp"` |  |
| tolerations | list | `[]` |  |
| useArgoSyncWaveAnnotations | bool | `false` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |
| webServers.livenessProbe.timeoutSeconds | int | `5` |  |
| webServers.port | int | `3000` |  |
| webServers.railsMaxThreads | int | `15` |  |
| webServers.readinessProbe.timeoutSeconds | int | `5` |  |
| webServers.replicas | int | `1` |  |
| webServers.resources.limits.memory | string | `"1.5Gi"` |  |
| webServers.resources.requests.cpu | int | `1` |  |
| webServers.resources.requests.memory | string | `"1Gi"` |  |
| workers.fingerprinter.dbFollowerPoolSize | int | `1` |  |
| workers.fingerprinter.dbPoolSize | int | `1` |  |
| workers.fingerprinter.fingerprinter.enabled | bool | `true` |  |
| workers.fingerprinter.fingerprinter.port | int | `6000` |  |
| workers.fingerprinter.fingerprinter.requests.cpu | int | `3` |  |
| workers.fingerprinter.fingerprinter.requests.memory | string | `"1Gi"` |  |
| workers.fingerprinter.queues[0].name | string | `"video_match_frames_native_fingerprint_tasks"` |  |
| workers.fingerprinter.queues[0].priority | int | `1` |  |
| workers.fingerprinter.replicas | int | `1` |  |
| workers.fingerprinter.resources.requests.cpu | string | `"50m"` |  |
| workers.fingerprinter.resources.requests.memory | string | `"1Gi"` |  |
| workers.fingerprinter.sidekiqConcurrency | int | `1` |  |
| workers.fingerprinter.sidekiqTimeout | int | `600` |  |
| workers.generic.queues[0].name | string | `"generic_queue"` |  |
| workers.generic.queues[0].priority | int | `1` |  |
| workers.generic.queues[1].name | string | `"generic_queue2"` |  |
| workers.generic.queues[1].priority | int | `2` |  |
| workers.generic.replicas | int | `1` |  |
| workers.generic.resources.requests.cpu | string | `"100m"` |  |
| workers.generic.resources.requests.memory | string | `"128Mi"` |  |
| workers.generic.sidekiqConcurrency | int | `5` |  |
| workers.generic.sidekiqTimeout | int | `25` |  |
| workers.ingest.queues[0].name | string | `"slow_queue"` |  |
| workers.ingest.queues[0].priority | int | `1` |  |
| workers.ingest.replicas | int | `1` |  |
| workers.ingest.resources.requests.cpu | string | `"100m"` |  |
| workers.ingest.resources.requests.memory | string | `"128Mi"` |  |
| workers.ingest.sidekiqConcurrency | int | `5` |  |
| workers.ingest.sidekiqTimeout | int | `25` |  |
| workers.process.queues[0].name | string | `"fast_queue"` |  |
| workers.process.queues[0].priority | int | `1` |  |
| workers.process.replicas | int | `1` |  |
| workers.process.resources.requests.cpu | string | `"100m"` |  |
| workers.process.resources.requests.memory | string | `"128Mi"` |  |
| workers.process.sidekiqConcurrency | int | `5` |  |
| workers.process.sidekiqTimeout | int | `25` |  |
