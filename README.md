# Helm Charts Repository

This repository hosts Helm charts for ad-signalio projects, published via GitHub Pages.

## Repository Structure

- **charts/** - Source files for Helm charts
- **docs/** - Packaged charts and repository index (published via GitHub Pages)

## Using This Helm Repository

Add this repository to your Helm client:

```bash
helm repo add ad-signalio https://ad-signalio.github.io/helm-charts
helm repo update
```

Search for available charts:

```bash
helm search repo ad-signalio
```

Install a chart:

```bash
helm install my-release-match match -n match -f values.yaml
```

## Automation

This repository uses GitHub Actions to automate chart releases. The workflow is triggered when:
- Changes are pushed to the `main` branch
- Changes affect files in the `charts/` directory

The `chart-releaser` action handles:
- Chart packaging
- GitHub release creation
- Repository index updates
- GitHub Pages publishing

Your Helm repository will be available at: `https://ad-signalio.github.io/helm-charts/`
