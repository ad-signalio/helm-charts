# Match Self Hosted Helm Chart

## Overview

This chart will install a self hosted Match service.

It is strongly suggested that you run this chart on a Kubernetes cluster dedicated to match. We provide a reference implementation suitable
for AWS [here](https://github.com/ad-signalio/match-reference-architecture)

# Requirements

A Kubernetes cluster with the following facilities:

## A ReadWriteMany PVC location

The application requires a shared Kubernetes ReadWriteMany Persistent Volume Claim across all pods to provide scratch space for the ingest and processing of
content into the system. Examples of this include AWS EFS, NFS and AssureFile.

`ReadWriteOnce` Persistent Volumes such as AWS EBS and Azure Disk are NOT suitable.

See the Kubernetes Persistent Volumes [Documentation](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) for more details.

For example, to use separately provisioned Persistent Volume named "customer-provided-pvc" for shared storage:

```
storage:
  sharedStorage:
    claimName: "customer-provided-pvc"
    size: 45000Gi
```

### Sizing the Volume
The shared storage will hold temporary copies of ingested content files during processing and should be sized according to the number of workers and size of content.

`workers.fingerprinter.replicas` + `workers.ingest.replicas` + `workers.process.queues` x Maximum Video file size x 1.5

For example in a small environment:

3 x fingerprinter workers
1 x ingest worker
1 x process worker
1 x audiofingerprint worker

Maximum Video Size = 500GB

(3 + 1 + 1 + 1 x 500GB) * 1.5 = 4500GB

## A Writeable /tmp directory

The TMP directory should be 1.5 x the size of the maximum Content.

The application requires a writable `/tmp` directory to use as temporary space while processing content.

By default a disk backed `emptyDir` is used. If the operator wishes to specify a different configuration this can
be modified in `.Values.volumes`. It is recommended that this is disk rather than memory backed as the system may store large content files in this location.

```
storage:
  ...
  tmpStorage:
    emptyDir:
      sizeLimit: 500Gi
```

## Optional Content via S3 compatible API

Content to ingest may be provided to the application via an S3 compatible endpoint.
Static Access Keys and Secret credentials to access an S3 compatible endpoint may be provided to in Match's web interface.

### Credentials via an AWS IAM with a Kubernetes Service Account (IRSA)

For content in an AWS S3 bucket an IAM Role assumable by a Kubernetes service account (IRSA) in an EKS pod may also be used by providing a IAM role ARN to annotate
the Service Account with.  See the AWS IAM Roles for service accounts [documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) for further information on how to configure the IAM role and EKS cluster.

```
serviceAccount:
  annotations:
   eks.amazonaws.com/role-arn: "arn:aws:iam::111122223333:role/my-role"
```

#### External Postgres Database

> It's is HIGHLY recommended you provide your own Postgres Database, and backups using a service such as AWS RDS.

Configure access to an externally managed database as below:

```
postgres:
  enabled: false
  database: match
  user: match
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
  password: bXlfc3VwZXJfc2VjcmV0X3Bhc3N3b3Jk  # Base64 encoded password
```

### Provisioning a Postgres database on the Kubernetes cluster

Optionally the chart can install a Postgres database on your Kubernetes cluster using the CloudPirates OpenSource [Postgres Helm Chart](https://github.com/CloudPirates-io/helm-charts/tree/main/charts/postgres).

> ** WARNING **
> This database is NOT suitable for production use in an unmodified form. Backups, nor High Availability or resiliency are not configured.

```
postgres:
  enabled: true
```

### Redis

> It's is **HIGHLY** recommended you provide your own Redis or compatible Database using a service such as AWS ElasticCache.

Configure access to an externally managed redis as below:

```
redis:
  enabled: false
redisSidekiq:
  uri: redis://redis.external-domain.tld:6379/
```

### Provisioning a Redis database on the Kubernetes cluster

Optionally the chart can install a Redis database on your Kubernetes cluster using the CloudPirates OpenSource [Redis Helm Chart](https://github.com/CloudPirates-io/helm-charts/tree/main/charts/redis).


> ** WARNING **
> This database is NOT suitable for production use in an unmodified form as High Availability or resiliency are **NOT** configured.


```
postgres:
  enabled: true
```

### ImagePullSecret credentials to Pull Images from Private Repository

The Match images require authentication to pull from our repositories. These credentials will be provided to you during initial setup.

A `kubernetes.io/dockerconfigjson`

Credentials can be added to your cluster using kubectl in the namespace the rest of the system is installed to (`match` in these examples).

```
kubectl -n match create secret docker-registry matchcredentials --docker-server=<your-registry-server> --docker-username=<your-name> --docker-password=<your-pword> --docker-email=<your-email>
```

The location of the imagePullSecret must then be configured in the values file:

```
imagePullSecrets:
  - name: "matchcredentials"
```

### Ingress and Domain

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

### Monitoring

The chart comes with dependencies that can install a Prometheus and Loki stack on the cluster to given access to log, metrics and dashboards.
These may require further configuration for your cluster's storage capabilities. You can bring your own monitoring and logging if you prefer.

```
monitoring:
  enabled: true
```

### Deploying with Argo

If the value `useArgoSyncWaveAnnotations` is set to `true`, the chart will use Argo Sync waves rather than helm hooks to configure ordering of data base migrations, service accounts and storage creation.