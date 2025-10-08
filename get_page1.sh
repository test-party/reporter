#!/bin/bash
set -euo pipefail

# ============================================
# Usage:
# ./get_job_status.sh <JOB_ID>
# ============================================

API_TOKEN="4c09596b-fe3d-489c-9bb6-b24cd9d6df26"
JOB_ID="$1"
API_BASE_STATUS="https://2a930ibq5j.execute-api.us-east-2.amazonaws.com/Stage/status"

# ============================================
# Helper function
# ============================================

fetch_status_page() {
  local jobId="$1"
  local token="$2"
  local page="$3"
  local limit="$4"
  curl -s -H "Authorization: Bearer $token" \
          -H "Content-Type: application/json" \
          "$API_BASE_STATUS/$jobId?page=$page&limit=$limit"
}

# ============================================
# Initial status check
# ============================================

limit=10
page=1
status_response=$(fetch_status_page "$JOB_ID" "$API_TOKEN" "$page" "$limit")

status=$(echo "$status_response" | jq -r '.status // .state // empty' | tr '[:upper:]' '[:lower:]')
processed=$(echo "$status_response" | jq -r '.processedChunks // 0')
total=$(echo "$status_response" | jq -r '.totalChunks // 0')
msg=$(echo "$status_response" | jq -r '.message // ""')

echo "🔄 Status: ${status:-unknown} | Chunks ${processed}/${total} ${msg:+| $msg}"

# ============================================
# Loop dynamically through pages
# ============================================

if [ "$status" = "completed" ]; then
  echo "✅ Scan completed successfully"
  echo "📥 Fetching results..."

  all_violations="[]"

  while true; do
    echo "🔍 Fetching page $page..."
    page_response=$(fetch_status_page "$JOB_ID" "$API_TOKEN" "$page" "$limit")

    # Ensure scanData is valid JSON
    page_scan_data=$(echo "$page_response" | jq '
      if (.scanData | type) == "object" then
        .scanData
      else
        {}
      end
    ')

    # Extract violations safely
    page_violations=$(echo "$page_scan_data" | jq '.violations // []')

    # Count safely
    count_results=$(echo "$page_violations" | jq -r 'length // 0' 2>/dev/null || echo 0)

    if [ "${count_results:-0}" -eq 0 ]; then
      echo "🚫 No more results found (page $page empty). Stopping."
      break
    fi

    # Count nodes for this page
    count_nodes=$(echo "$page_violations" | jq '([.[] | .results | map(.nodes | length) | add] | add) // 0')
    echo "   ↳ Found $count_results URLs ($count_nodes total elements)"

    # Merge globally
    all_violations=$(jq -s 'add' <(echo "$all_violations") <(echo "$page_violations"))

    ((page++))
  done

  # ============================================
  # Print detailed results
  # ============================================

  echo "--------------------------------------------"
  echo "📊 Processing detailed results..."
  echo "--------------------------------------------"

  echo "$all_violations" | jq -r '
    .[] | "
🔍 URL: \(.url)
Found \((.results | map(.nodes | length) | add) // 0) violations

Detailed Violations:
\(.results[] |
  "Impact: \(.impact)
Rule: \(.id)
Description: \(.description)
Elements Affected: \(.nodes | length)
---")"
  '

  # ============================================
  # Summary per URL + report info
  # ============================================

  echo "--------------------------------------------"
  echo "📊 Summary by URL:"
  echo "--------------------------------------------"
  echo "$all_violations" | jq -r '.[] | "\(.url): \((.results | map(.nodes | length) | add) // 0) violations"'

  # Report URL
  report_uri=$(echo "$status_response" | jq -r '.scanData.reportUri // .reportUri // empty')
  if [ -n "$report_uri" ] && [ "$report_uri" != "null" ]; then
    echo "--------------------------------------------"
    echo "📄 Report URL: $report_uri"
  fi

  # Total violations
  total_violations=$(echo "$all_violations" | jq '[.[] | .results | map(.nodes | length) | add] | add // 0')
  echo "--------------------------------------------"
  echo "📈 Total violations across all URLs: $total_violations"

else
  echo "❌ Scan not completed yet"
  echo "Current status: $status"
  echo "Progress: $processed / $total chunks"
fi
