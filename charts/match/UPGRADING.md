# Upgrade Notes

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
