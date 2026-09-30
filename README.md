# ad-signalio/helm-charts — deprecated

**This repository is no longer maintained. It has moved to
[snicketlabs/helm-charts](https://github.com/snicketlabs/helm-charts).**

No new chart versions will be published here. The index at
<https://ad-signalio.github.io/helm-charts> is frozen at its last state and will
be taken down after a notice period.

## Switch to the new repository

```bash
helm repo remove ad-signalio
helm repo add snicketlabs https://snicketlabs.github.io/helm-charts
helm repo update
helm search repo snicketlabs
```

## Where each chart went

| Published here | Now | Notes |
|---|---|---|
| `secrets-configuration-aws` | `snicketlabs/secrets-configuration-aws` | Same chart, same name |
| `secrets-configuration-gcp` | `snicketlabs/secrets-configuration-gcp` | Same chart, same name |
| `adsignal-match` | `snicketlabs/platform` | **Not an upgrade. See below.** |

### `adsignal-match` has no upgrade path

`platform` is a fork of `adsignal-match`, not a renamed continuation of it. The
release names, resource names and values differ. `helm upgrade` from an
`adsignal-match` release to `platform` is not supported and is not tested.

Moving an existing install means a fresh `helm install` of `platform` and a
migration of state. Talk to us before attempting it.

### Licensed releases go via OCI, not this repo

The public chart repository carries the open charts. Licensed platform releases
are distributed from our registry:

```bash
helm install oci://registry.snicketlabs.io/snicketlabs/platform-chart/platform
```

That route needs credentials. If you have a licence and no credentials, contact
Snicket Labs.

## Why this repository still exists

It is archived and read-only so the published history and the frozen index stay
resolvable while consumers migrate. Everything in `charts/` here is superseded
by the new repository — do not use it as a source.
