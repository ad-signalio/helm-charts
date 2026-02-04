# Match Self Hosted Helm Chart

## Overview

This chart will install a self hosted Match service.

It is strongly suggested that you run this chart on a Kubernetes cluster dedicated to match. We provide a reference implementation suitable
for AWS [here](https://github.com/ad-signalio/match-environment/)

## Requirements

A Kubernetes cluster with the following facilities:

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
      sizeLimit: 500Gi
```

> Please consult with Ad-Signal technical services for sizing recommendations.

### S3 Buckets

The application makes use of two types of S3 buckets:

- **Primary Bucket**: This is the main storage bucket for the application where artifacts are stored.

- **Content Bucket**: These are buckets containing the source media files that you wish to ingest into the system.

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
  database: match
  username: match
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

## Image Pull Secrets

The Match images require authentication to pull from our repositories. These credentials will be provided to you during initial setup.

For example, to create a `kubernetes.io/dockerconfigjson` secret:

```
kubectl -n match create secret docker-registry matchcredentials --docker-server=<your-registry-server> --docker-username=<your-name> --docker-password=<your-pword> --docker-email=<your-email>
```

(Credentials can be added to your cluster using kubectl in the namespace the rest of the system is installed to (`match` in these examples).)

The location of the imagePullSecret must then be configured in the values file:

```
imagePullSecrets:
  - name: "matchcredentials"
```

> We reccomend using a method to manage your kubernetes secrets, such as AWS Secrets Manager CSI Driver, External Secrets Operator, Vault, or another secret management solution of your choice.

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

Use this as a checklist when creating your own `your-custom-values.yaml` file.

## 1. Image Tags

Specify image versions (usually provided by Ad Signal during deployment).

```yaml
image:
  repository: adsignal/hub
  tag: sha-EXAMPLE  # Update to your desired version

fingerprinter:
  image:
    repository: adsignal/stream-fp
    tag: "x86_64-linux-sha-EXAMPLE"  # Update to your desired version
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

Configure AWS Load Balancer Controller ingress.

```yaml
ingress:
  enabled: true
  className: "alb"
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: {YOUR_CERTIFICATE_ARN}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /users/sign_in
    alb.ingress.kubernetes.io/success-codes: "200-402"
    external-dns.alpha.kubernetes.io/hostname: {YOUR_DOMAIN}

  hosts:
    - host: {YOUR_DOMAIN}
      paths:
        - path: /
          pathType: Prefix
```

## 5. Database and Redis Configuration

### PostgreSQL (RDS)

> See the reference architecture for AWS Secrets Manager configuration and EKS ascp add-on. The below example is for quickstart manual configuration and we recommend using a secret manager.

> See the reference architecture for AWS RDS and ElastiCache configuration

**QuickStart**: Configure connection to your external RDS PostgreSQL database using direct values:

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

Create a Kubernetes secret for the database password:

```bash
kubectl create secret generic match-postgres-password \
  --namespace match \
  --from-literal=password='YOUR_DATABASE_PASSWORD'
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

Create a primary S3 bucket for the application.

> Consult the reference architecture for AWS S3 configuration.

Configure your primary S3 bucket in the values file:

```yaml
s3:
  primaryBucket: your-s3-bucket-name  # Your S3 bucket name
  region: us-east-1                   # Your AWS region
```

> Ensure your IAM role (IRSA) has appropriate S3 permissions for the bucket.

## 7. Image Pull Secrets

For configuring image pull secrets to authenticate with the Ad Signal container registry, see the [Image Pull Secrets](README.md#image-pull-secrets) section in the main README.

---

## Quick Start Checklist

Use this checklist to ensure you've configured all required values:

- [ ] Created and configured `imagePullSecrets`
- [ ] Configured shared storage with ReadWriteMany PVC - (Optionally: See Reference Architecture)
- [ ] Created IAM role for service account (IRSA) - (Optionally: See Reference Architecture)
- [ ] Configured S3 bucket - (Optionally: See Reference Architecture)
- [ ] Obtained ACM certificate for your domain - (Optionally: See Reference Architecture)
- [ ] Updated domain name in all relevant places
- [ ] Configured ingress annotations with correct ARNs

---

## Deployment Command

Once you've customized your `values.yaml` file, install the chart with the relevant size file:

> Please consult with Ad-Signal technical services for sizing recommendations.

```bash
helm repo add ad-signal https://ad-signalio.github.io/helm-charts
```

```bash
helm install ad-signal/adsignal-match  \
  --namespace match \
  --generate-name \
  --create-namespace \
  --values your-custom-values.yaml -f environment-sizes/{SIZE}.yaml
```



### Retrieving the Initial Password

The helm command above will output the kubectl command to retrieve the initial user password, if you are unable to use this (Argo, Flux, etc.) you can use the kubectl command below:

```bash
kubectl get secret adsignal-match-owning-user -n match -o jsonpath='{.data.password}' | base64 -d
```

----

## Getting Help

> For sizing recommendations, production configuration guidance, or deployment assistance, please consult with Ad Signal technical services.

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
- [ ] Set up monitoring and alerting (Prometheus, Grafana, Loki) # Please consult with Ad Signal technical services for production-ready solutions
- [ ] Configured database backups and disaster recovery procedures
- [ ] Reviewed and optimized resource requests and limits based on actual usage


