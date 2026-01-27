# Helm Charts Repository

This repository hosts Helm charts for ad-signalio projects, published via GitHub Pages.

## Repository Structure

- **charts/** - Source files for Helm charts
- **docs/** - Packaged charts and repository index (published via GitHub Pages)

## Using This Helm Repository

Add this repository to your Helm client:

```bash
helm repo add ad-signalio https://ad-signalio.github.io/helm-charts/
helm repo update
```

Search for available charts:

```bash
helm search repo ad-signalio
```

Install a chart:

```bash
helm install my-release ad-signalio/<chart-name>
```

## Contributing Charts

### Creating a New Chart

1. Create a new directory in the `charts/` folder:
   ```bash
   mkdir charts/my-chart
   ```

2. Initialize your chart structure:
   ```bash
   helm create charts/my-chart
   ```

3. Customize your chart by editing:
   - `Chart.yaml` - Chart metadata
   - `values.yaml` - Default configuration values
   - `templates/` - Kubernetes resource templates

4. Test your chart locally:
   ```bash
   helm lint charts/my-chart
   helm install test-release charts/my-chart --dry-run --debug
   ```

### Publishing Charts

Charts are automatically packaged and published when changes are pushed to the `main` branch:

1. Commit your chart to the `charts/` directory
2. Push to the `main` branch
3. GitHub Actions will automatically:
   - Package the chart
   - Create a GitHub release
   - Update the Helm repository index in the `docs/` folder

## Automation

This repository uses GitHub Actions to automate chart releases. The workflow is triggered when:
- Changes are pushed to the `main` branch
- Changes affect files in the `charts/` directory

The `chart-releaser` action handles:
- Chart packaging
- GitHub release creation
- Repository index updates
- GitHub Pages publishing

## Repository Setup

To enable GitHub Pages for this repository:

1. Go to repository Settings
2. Navigate to Pages section
3. Set Source to "Deploy from a branch"
4. Select branch: `main`
5. Select folder: `/docs`
6. Save the configuration

Your Helm repository will be available at: `https://ad-signalio.github.io/helm-charts/`