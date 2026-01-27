# Charts Directory

This directory contains the source files for Helm charts.

## Structure

Each chart should be in its own subdirectory:

```
charts/
├── chart-name/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── templates/
│   └── ...
```

## Adding a New Chart

1. Create a new directory for your chart in this folder
2. Follow the standard Helm chart structure
3. Commit your changes
4. The CI/CD pipeline will automatically package and publish the chart

## Development

To test a chart locally:

```bash
helm lint charts/your-chart
helm install test-release charts/your-chart --dry-run --debug
```
