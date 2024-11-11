# 🎯 TestParty:Reporter

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Accessibility%20Scanner-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAM6wAADOsB5dZE0gAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAERSURBVCiRhZG/SsMxFEZPfsVJ61jbxaF0cRQRcRJ9hlYn30IHN/+9iquDCOIsblIrOjqKgy5aKoJQj4O3EEtbPwhJbr6Te28CmdSKeqzeqr0YbfVIrTBKakvtOl5dtTkK+v4HfA9PEyBFCY9AGVgCBLaBp1jPAyfAJ/AAdIEG0dNAiyP7+K1qIfMdonZic6+WJoBJvQlvuwDqcXadUuqPA1NKAlexbRTAIMvMOCjTbMwl1LtI/6KWJ5Q6rT6Ht1MA58AX8Apcqqt5r2qhrgAXQC3CZ6i1+KMd9TRu3MvA3aH/fFPnBodb6oe6HM8+lYHrGdRXW8M9bMZtPXUji69lmf5Cmamq7quNLFZXD9Rq7v0Bpc1o/tp0fisAAAAASUVORK5CYII=)](https://github.com/marketplace/actions/testparty-reporter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- ![Test Status](https://github.com/your-username/repo-name/workflows/Test/badge.svg) -->

Automatically scan your web applications for accessibility violations using our advanced rules engine. This GitHub Action helps ensure your websites maintain WCAG compliance by running scheduled scans on your specified URLs.

## ✨ Features

- 🔄 Automated accessibility scanning on a schedule
- 🎯 Custom rules engine based on WCAG guidelines
- 📊 Detailed violation reporting
- 🔗 Support for multiple URLs

## 🚀 Quick Start

1. Create a new workflow in your repository (e.g., `.github/workflows/testparty.yml`):

```yaml
name: Accessibility Scan
on:
  schedule:
    - cron: '0 0 * * *'  # Runs daily at midnight UTC
  workflow_dispatch:      # Allows manual triggers

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - name: Run Accessibility Scan
        uses: your-username/accessibility-scanner@v1
        with:
          api_token: ${{ secrets.ACCESSIBILITY_API_TOKEN }}
          urls: 'https://example.com,https://example.com/about'
```

## 🔧 Configuration

### Required Inputs

| Input | Description |
|-------|-------------|
| `api_token` | Your API token for authentication. Must be stored as a repository secret. |
| `urls` | Comma-separated list of URLs to scan (e.g., 'https://example.com,https://example.com/about') |

### Setting Up Secrets

1. Navigate to your repository's settings
2. Go to "Secrets and variables" → "Actions"
3. Click "New repository secret"
4. Create a secret named `TESTPARTY_TOKEN`
5. Paste your API token value and click "Add secret"

### Schedule Configuration

The action uses GitHub's cron syntax for scheduling. Here are some common examples:

```yaml
schedule:
  - cron: '0 0 * * *'    # Daily at midnight UTC
  - cron: '0 */6 * * *'  # Every 6 hours
  - cron: '0 * * * *'    # Every hour
  - cron: '*/15 * * * *' # Every 15 minutes