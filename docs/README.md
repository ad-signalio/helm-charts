# Docs Directory

This directory will contain packaged Helm charts and the repository index for GitHub Pages.

## Purpose

This folder serves as the root of the Helm repository that will be published via GitHub Pages. Once charts are packaged, it will contain:

- `index.yaml` - The repository index file
- `*.tgz` - Packaged chart archives

## Current Charts

The following charts are available in this repository:

- **match** - Ad-Signal Match Self Hosted (v0.1.0)

## Getting Started 

To add this Helm repository to your local Helm client:

```
helm repo add match https://ad-signalio.github.io/helm-charts
helm repo update
```

## Important

Do not manually modify files in this directory. They are automatically generated and updated by the CI/CD pipeline when charts are added or updated in the `charts/` directory.