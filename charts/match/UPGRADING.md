# Upgrade Notes

## 3.1.0

No manual steps are required. This release changes worker resource defaults and
fixes autoscaling for the `generic-worker` pool, so review the capacity note
below before upgrading a cluster with fixed-size nodes.

### What changed

`compare-relate` was OOMKilled at its old 1Gi limit when aligning long-form
material. Measured peak RSS aligning a pair of 180-minute assets is **1083 MiB**,
i.e. above the 1024 MiB the old limit allowed, which is why the failure looked
intermittent — shorter pairs fitted underneath it.

| `scaledJobs.compare-relate` | 3.0.0 | 3.1.0 |
|---|---|---|
| `resources.requests.memory` | 1Gi | **3Gi** |
| `resources.limits.memory` | 1Gi | **3Gi** |
| `resources.requests.cpu` | 0.5 | 0.5 *(unchanged)* |
| `resources.limits.cpu` | 0.5 | **2** |
| `activeDeadlineSeconds` | 600 | **14400** |

`scaledJobs.process-whole-media-compare.activeDeadlineSeconds` also goes from
600 to **3600**. That queue searches the whole organisation for comparison
candidates, so its runtime grows with how much material the organisation holds;
at 600s it was killed part-way through on a catalogue of 41 comparable items.

### Capacity note — check this before upgrading

The only change that needs planning is **memory**. `compare-relate` keeps
`requests` equal to `limits` on memory, so this is a reservation the scheduler
must satisfy, not a ceiling:

- **Each pod now needs a node with at least 3Gi allocatable.** A node that
  previously hosted these pods comfortably may no longer fit one. For reference,
  an AWS `c6a.large` (≈3.0Gi allocatable) cannot schedule one at all.
- **The stage's total reservation triples**, at `maxReplicaCount` × 3Gi:

  | profile | 3.0.0 | 3.1.0 |
  |---|---|---|
  | default / `small` (5) | 5Gi | 15Gi |
  | `medium` (10) | 10Gi | 30Gi |
  | `large` (15) | 15Gi | 45Gi |

If your nodes are autoscaled, larger nodes will be provisioned on demand and no
action is needed. If you run fixed-size nodes, confirm the headroom exists first
— otherwise `compare-relate` pods will sit in `Pending` and comparison work will
stall. To trade throughput for a smaller footprint, lower
`scaledJobs.compare-relate.maxReplicaCount` rather than the memory values.

The CPU **request** is deliberately unchanged at 0.5, so this release adds no
CPU reservation and will not cause nodes to be provisioned on CPU grounds. Only
the limit rose, letting the alignment use up to 2 cores when it has work to do.

### `generic-worker` autoscaling now functions

KEDA's redis scaler requires a bare `host:port` address, but the chart passed it
the full `rediss://` URL for `scaledObjects`. KEDA could not create the HPA, so
`generic-worker` stayed at `minReplicaCount` and never responded to queue depth.
This is fixed.

**Expect it to start scaling after upgrading.** On a busy queue you will see
`generic-worker` replicas grow up to `maxReplicaCount` where previously they did
not, with a corresponding rise in cluster resource usage. That is the intended
behaviour, and it was silently absent before. If the new ceiling is higher than
you want, set `scaledObjects.generic-worker.maxReplicaCount`.

### Longer kill times for genuinely stuck jobs

The raised `activeDeadlineSeconds` values are backstops for a hung process, not
working budgets — the measured long-form cases complete in 45s and ~95s
respectively. The trade-off is that a job which is truly stuck now takes longer
to be killed and retried. If you alert on job duration, adjust those thresholds
to match.

---

## 3.0.0

This is a breaking release. Several chart-level changes require one-time manual steps before running `helm upgrade`. Read this section carefully before upgrading.

### Breaking changes summary

| Change | Impact |
|---|---|
| `s3.endpoint` / `s3.credentialsSecret` renamed to `s3.compatibleEndpoint` / `s3.compatibleCredentialsSecret` etc. | Existing GCS/Ceph values files will silently stop injecting S3 env vars — update values before upgrading |
| ServiceAccount converted from Helm hook to regular resource | Helm will refuse to adopt it without ownership annotations — run adoption commands first |
| Shared storage PVC skipped on upgrade | Helm will orphan-delete it on the first upgrade — annotate it first |
| `INGEST_CREDENTIAL_ENCRYPTION_KEY` now generated as 32 bytes (was 64) | Fresh installs will work correctly; existing installs are unaffected (key is preserved from the existing secret) |

---

### 1. Update S3-compatible storage values (if applicable)

If your values file uses `s3.endpoint`, `s3.publicEndpoint`, or `s3.credentialsSecret`, rename them before upgrading:

| Old key | New key |
|---|---|
| `s3.endpoint` | `s3.compatibleEndpoint` |
| `s3.publicEndpoint` | `s3.compatiblePublicEndpoint` |
| `s3.credentialsSecret` | `s3.compatibleCredentialsSecret` |

Two new optional keys allow overriding the credential secret's key names (useful for Rook OBC secrets that use `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` instead of the default `access_key_id` / `secret_access_key`):

```yaml
s3:
  compatibleAccessKeyField: "AWS_ACCESS_KEY_ID"    # default: access_key_id
  compatibleSecretKeyField: "AWS_SECRET_ACCESS_KEY" # default: secret_access_key
```

AWS deployments using IRSA are unaffected — leave all `s3.compatible*` keys empty.

---

### 2. Adopt the ServiceAccount into Helm (one-time manual step)

Prior to 3.0.0 the `adsignal-match` ServiceAccount was a Helm hook. It is now a regular chart resource. Because hooks are created without Helm ownership annotations, upgrading will fail with:

```
Error: UPGRADE FAILED: Unable to continue with update: ServiceAccount "adsignal-match" in
namespace "<namespace>" exists and cannot be imported into the current release: invalid
ownership metadata; annotation validation error: missing key "meta.helm.sh/release-name"
```

Run the following **once** before upgrading, substituting your release name and namespace:

```bash
kubectl annotate serviceaccount adsignal-match \
  -n <namespace> \
  meta.helm.sh/release-name=<release-name> \
  meta.helm.sh/release-namespace=<namespace> \
  --overwrite

kubectl label serviceaccount adsignal-match \
  -n <namespace> \
  app.kubernetes.io/managed-by=Helm \
  --overwrite
```

---

### 3. Protect the shared storage PVC (one-time manual step)

Prior to 3.0.0 the `match-shared-storage` PVC was a regular Helm-managed resource. It is now skipped on upgrade to avoid immutable-field conflicts. On the first upgrade Helm will see it as orphaned and **delete it, destroying all stored media**, unless you annotate it first.

Run the following **before upgrading**:

```bash
# Prevent Helm from orphan-deleting the PVC
kubectl annotate persistentvolumeclaim match-shared-storage \
  -n <namespace> \
  helm.sh/resource-policy=keep \
  --overwrite

# Change the underlying PV reclaim policy to Retain as a safety net
PV=$(kubectl get pvc match-shared-storage -n <namespace> -o jsonpath='{.spec.volumeName}')
kubectl patch pv $PV -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

Fresh installs from 3.0.0 onwards have `helm.sh/resource-policy: keep` set automatically.
