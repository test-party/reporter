#!/bin/bash
set -euo pipefail

# ============================================
# Usage:
# ./run_scan.sh <API_TOKEN> <REPOSITORY_NAME> <REPOSITORY_ID> <URLS_JSON> <SETUP_JSON> <TEARDOWN_JSON>
# ============================================

API_TOKEN="$1"
REPOSITORY_NAME="$2"
REPOSITORY_ID="$3"
URLS="$4"
SETUP="$5"
TEARDOWN="$6"

# API endpoints
API_POST_PROCESS="https://2a930ibq5j.execute-api.us-east-2.amazonaws.com/Stage/process"
API_BASE_STATUS="https://2a930ibq5j.execute-api.us-east-2.amazonaws.com/Stage/status"

# ============================================
# Helper functions
# ============================================

check_job_status() {
  local jobId="$1"
  local token="$2"
  curl -s \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "$API_BASE_STATUS/$jobId"
}

fetch_status_page() {
  local jobId="$1"
  local token="$2"
  local page="$3"
  local limit="$4"
  curl -s \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "$API_BASE_STATUS/$jobId?page=$page&limit=$limit"
}

# ============================================
# Launch the scan
# ============================================

OPTIONS="{\"setup\": $SETUP, \"teardown\": $TEARDOWN}"
REQUEST_BODY="{\"urls\": $URLS, \"process\": \"github_action\", \"project\": {\"name\": \"$REPOSITORY_NAME\", \"github_id\": $REPOSITORY_ID}, \"options\": $OPTIONS}"

echo "📋 Initiating scan for URLs"
echo "Request Body: $REQUEST_BODY"

response=$(curl -s -H "Authorization: Bearer $API_TOKEN" \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$REQUEST_BODY" \
                "$API_POST_PROCESS")

jobId=$(echo "$response" | jq -r '.jobId')
if [ -z "${jobId:-}" ] || [ "$jobId" = "null" ]; then
  echo "❌ Failed to get jobId"
  echo "Response: $response"
  exit 1
fi
echo "✅ Scan initiated - Task ID: $jobId"

# ============================================
# Poll for job completion
# ============================================

status="pending"
max_attempts=720  # 1 hour (5s * 720)
attempt=0

while :; do
  if [ $attempt -ge $max_attempts ]; then
    echo "❌ Timeout waiting for results"
    break
  fi

  sleep 5
  status_response=$(check_job_status "$jobId" "$API_TOKEN")

  status=$(echo "$status_response" | jq -r '.status // .state // empty' | tr '[:upper:]' '[:lower:]')
  processed=$(echo "$status_response" | jq -r '.processedChunks // 0')
  total=$(echo "$status_response" | jq -r '.totalChunks // 0')

  msg=$(echo "$status_response" | jq -r '.message // ""')

  echo "🔄 Status: ${status:-unknown} | Chunks ${processed}/${total}"

  if [ "$status" = "completed" ] || [ "$status" = "failed" ]; then
    break
  fi

  ((attempt++))
done

# ============================================
# Process and display results (from completed scan)
# ============================================

if [ "$status" = "completed" ]; then
  echo "✅ Scan completed successfully"
  echo "📥 Fetching results..."

  all_violations="[]"
  page=1
  limit=10

  while true; do
    echo "🔍 Fetching page $page..."
    page_response=$(fetch_status_page "$jobId" "$API_TOKEN" "$page" "$limit")

    # Guarantee scanData is valid
    page_scan_data=$(echo "$page_response" | jq '
      if (.scanData | type) == "object" then
        .scanData
      else
        {}
      end
    ')

    # Extract violations safely
    page_violations=$(echo "$page_scan_data" | jq '.violations // []')
    count_results=$(echo "$page_violations" | jq -r 'length // 0' 2>/dev/null || echo 0)

    if [ "${count_results:-0}" -eq 0 ]; then
      echo "🚫 No more results found (page $page empty). Stopping."
      break
    fi

    count_nodes=$(echo "$page_violations" | jq '([.[] | .results | map(.nodes | length) | add] | add) // 0')
    echo "   ↳ Found $count_results URLs ($count_nodes total elements)"

    all_violations=$(jq -s 'add' <(echo "$all_violations") <(echo "$page_violations"))
    ((page++))
  done

  echo "--------------------------------------------"
  echo "📊 Processing detailed results..."
  echo "--------------------------------------------"

  # Detailed violations per URL
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

  # Summary per URL
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
  echo "❌ Scan failed or timed out"
  echo "Final status: $status"
  if [ -n "${msg:-}" ]; then
    echo "Final message: $msg"
  fi
fi
