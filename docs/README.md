# Docs Directory

This directory contains packaged Helm charts and the repository index for GitHub Pages.

## Purpose

This folder serves as the root of the Helm repository that is published via GitHub Pages. It contains:

- `index.yaml` - The repository index file
- `*.tgz` - Packaged chart archives

## Important

Do not manually modify files in this directory. They are automatically generated and updated by the CI/CD pipeline when charts are added or updated in the `charts/` directory.
