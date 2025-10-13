# 🎯 TestParty:Reporter

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-TestParty%20Reporter-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAM6wAADOsB5dZE0gAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAERSURBVCiRhZG/SsMxFEZPfsVJ61jbxaF0cRQRcRJ9hlYn30IHN/+9iquDCOIsblIrOjqKgy5aKoJQj4O3EEtbPwhJbr6Te28CmdSKeqzeqr0YbfVIrTBKakvtOl5dtTkK+v4HfA9PEyBFCY9AGVgCBLaBp1jPAyfAJ/AAdIEG0dNAiyP7+K1qIfMdonZic6+WJoBJvQlvuwDqcXadUuqPA1NKAlexbRTAIMvMOCjTbMwl1LtI/6KWJ5Q6rT6Ht1MA58AX8Apcqqt5r2qhrgAXQC3CZ6i1+KMd9TRu3MvA3aH/fFPnBodb6oe6HM8+lYHrGdRXW8M9bMZtPXUji69lmf5Cmamq7quNLFZXD9Rq7v0Bpc1o/tp0fisAAAAASUVORK5CYII=)](https://github.com/marketplace/actions/testparty-reporter)
[![License: MIT](https://img.shields.io/badge/License-agplv3-blue.svg)](https://opensource.org/licenses/agplv3)

Automatically scan your web applications for accessibility violations using our advanced rules engine. This GitHub Action helps ensure your websites maintain WCAG compliance by running scheduled scans on your specified URLs.

## ✨ Features

- 🔄 Automated accessibility scanning on a schedule
- 🎯 Custom rules engine based on WCAG guidelines
- 📊 Detailed violation reporting
- 🔗 Support for multiple URLs with custom interaction steps
- 📁 Flexible configuration: inline URLs or JSON file

## 🚀 Quick Start

## Create a worflow file (eg: .github/workflows/scan.yml)

### Option 1: Inline URLs (Recommended for simple scans)

Perfect for scanning a few URLs without complex interactions:

```yaml
name: TestParty Reporter
on:
  schedule:
    - cron: '0 3 * * *'  # Runs daily at 3 AM UTC
  workflow_dispatch:      # Allows manual triggers

jobs:
  accessibility-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: TestParty Reporter
        uses: test-party/reporter@main
        with:
          testparty_token: ${{ secrets.TESTPARTY_TOKEN }}
          repository_name: ${{ github.repository }}
          repository_id: ${{ github.repository_id }}
          urls: |
            [
              {
                "url": "https://example.com",
                "steps": []
              },
              {
                "url": "https://example.com/about",
                "steps": []
              },
              {
                "url": "https://example.com/contact",
                "steps": []
              }
            ]
          setup: |
            []
          teardown: |
            []
```

### Option 2: JSON File (Recommended for complex scans)

Ideal for managing multiple URLs with custom interaction steps:

1. Create a JSON file (e.g., `.github/workflows/urls.json`):

```json
{
  "urls": [
    {
      "url": "https://example.com",
      "steps": []
    },
    {
      "url": "https://example.com/login",
      "steps": []
    },
    {
      "url": "https://example.com/dashboard",
      "steps": []
    }
  ]
}
```

2. Create your workflow file (e.g., `.github/workflows/testparty.yml`):

```yaml
name: TestParty Reporter
on:
  schedule:
    - cron: '0 3 * * *'  # Runs daily at 3 AM UTC
  workflow_dispatch:      # Allows manual triggers

jobs:
  accessibility-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: TestParty Reporter
        uses: test-party/reporter@main
        with:
          testparty_token: ${{ secrets.TESTPARTY_TOKEN }}
          repository_name: ${{ github.repository }}
          repository_id: ${{ github.repository_id }}
          urls: ".github/workflows/urls.json"
          setup: |
            []
          teardown: |
            []
```

## 🔧 Configuration

### Required Inputs

| Input | Description | Example |
|-------|-------------|---------|
| `testparty_token` | Your TestParty API token (store as secret) | `${{ secrets.TESTPARTY_TOKEN }}` |
| `repository_name` | Repository name | `${{ github.repository }}` |
| `repository_id` | Repository ID | `${{ github.repository_id }}` |


### Optional Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `setup` | JSON array of setup steps to run before scanning | `[]` |
| `teardown` | JSON array of teardown steps to run after scanning | `[]` |

### URL Object Structure

Each URL object in your configuration must follow this structure:

```json
{
  "url": "https://example.com/page",
  "steps": []
}
```

### Setting Up Secrets

1. Navigate to your repository's **Settings**
2. Go to **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Create a secret named `TESTPARTY_TOKEN`
5. Paste your API token value and click **Add secret**

> 🔐 **Never commit your API token directly in workflow files!**

## 📅 Schedule Configuration

The action uses GitHub's cron syntax for scheduling. Here are common examples:

```yaml
schedule:
  # Daily at 3 AM UTC
  - cron: '0 3 * * *'
  
  # Every 6 hours
  - cron: '0 */6 * * *'
  
  # Every Monday at 9 AM UTC
  - cron: '0 9 * * 1'
  
  # Twice daily (6 AM and 6 PM UTC)
  - cron: '0 6,18 * * *'
```

> 💡 **Tip:** Use [crontab.guru](https://crontab.guru/) to generate and validate cron expressions.

## 📖 Complete Examples

### Example 1: Simple E-commerce Site

```yaml
name: Accessibility Scan - Store
on:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Scan Store Pages
        uses: test-party/reporter@main
        with:
          testparty_token: ${{ secrets.TESTPARTY_TOKEN }}
          repository_name: ${{ github.repository }}
          repository_id: ${{ github.repository_id }}
          urls: |
            [
              {
                "url": "https://store.example.com",
                "steps": []
              },
              {
                "url": "https://store.example.com/products",
                "steps": []
              },
              {
                "url": "https://store.example.com/cart",
                "steps": []
              }
            ]
          setup: |
            []
          teardown: |
            []
```

### Example 2: Multi-page Blog

Create `.github/workflows/blog-urls.json`:

```json
{
  "urls": [
    {
      "url": "https://blog.example.com",
      "steps": []
    },
    {
      "url": "https://blog.example.com/search",
      "steps": []
    },
    {
      "url": "https://blog.example.com/contact",
      "steps": []
    }
  ]
}
```

Create `.github/workflows/blog-scan.yml`:

```yaml
name: Blog Accessibility Scan
on:
  schedule:
    - cron: '0 8 * * 1'  # Every Monday at 8 AM
  workflow_dispatch:

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Scan Blog
        uses: test-party/reporter@main
        with:
          testparty_token: ${{ secrets.TESTPARTY_TOKEN }}
          repository_name: ${{ github.repository }}
          repository_id: ${{ github.repository_id }}
          urls_json_file: ".github/workflows/blog-urls.json"
          setup: |
            []
          teardown: |
            []
```

## 🐛 Troubleshooting

### Common Issues

**Issue:** `❌ Either 'urls' or 'urls_json_file' must be provided`
- **Solution:** Make sure you provide exactly one of these inputs (not both, not neither)

**Issue:** `❌ JSON syntax invalid`
- **Solution:** Validate your JSON using [jsonlint.com](https://jsonlint.com/)

**Issue:** `❌ No URLs found`
- **Solution:** Ensure your JSON has a non-empty `urls` array

**Issue:** `❌ Failed to get jobId`
- **Solution:** Check that your `TESTPARTY_TOKEN` is valid and properly set

## 📝 License

This project is licensed under the AGPLv3 License.

## 🤝 Support

- 📧 Email: support@testparty.ai
- 🐛 Issues: [GitHub Issues](https://github.com/test-party/reporter/issues)
- 📚 Documentation: [TestParty Docs](https://docs.testparty.ai)

---

Made with ❤️ by TestParty