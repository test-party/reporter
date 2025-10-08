#!/bin/bash
set -euo pipefail

# ============================================
# Usage:
# ./run_scan.sh <API_TOKEN> <REPOSITORY_NAME> <REPOSITORY_ID> <URLS_JSON_FILE> <SETUP_JSON> <TEARDOWN_JSON>
# ============================================

API_TOKEN="$1"
REPOSITORY_NAME="$2"
REPOSITORY_ID="$3"
URLS_JSON_FILE="$4"
SETUP="$5"
TEARDOWN="$6"

API_POST_PROCESS="https://api.testparty.ai/v2/scan"
API_BASE_STATUS="https://api.testparty.ai/v2/scan/status"

check_job_status() {
  local jobId="$1"
  local token="$2"
  curl -s -H "Authorization: Bearer $token" -H "Content-Type: application/json" "$API_BASE_STATUS/$jobId"
}

fetch_status_page() {
  local jobId="$1"
  local token="$2"
  local page="$3"
  local limit="$4"
  curl -s -H "Authorization: Bearer $token" -H "Content-Type: application/json" "$API_BASE_STATUS/$jobId?page=$page&limit=$limit"
}

# ============================================
# Validate URLs file
# ============================================

URLS_FILE="/tmp/urls_clean.json"

if [ -z "${URLS_JSON_FILE:-}" ] || [ ! -f "$URLS_JSON_FILE" ]; then
  echo "❌ URLs file not found: $URLS_JSON_FILE"
  exit 1
fi

echo "📄 Using URLs from: $URLS_JSON_FILE"
file_size=$(stat -c%s "$URLS_JSON_FILE" 2>/dev/null || stat -f%z "$URLS_JSON_FILE" 2>/dev/null)
file_size_kb=$((file_size / 1024))
echo "📊 File size: ${file_size_kb} KB ($file_size bytes)"

open_braces=$(grep -o '{' "$URLS_JSON_FILE" | wc -l | tr -d ' ')
close_braces=$(grep -o '}' "$URLS_JSON_FILE" | wc -l | tr -d ' ')
open_brackets=$(grep -o '\[' "$URLS_JSON_FILE" | wc -l | tr -d ' ')
close_brackets=$(grep -o '\]' "$URLS_JSON_FILE" | wc -l | tr -d ' ')

if [ "$open_braces" -ne "$close_braces" ] || [ "$open_brackets" -ne "$close_brackets" ]; then
  echo "❌ Invalid JSON structure (unbalanced braces/brackets)"
  exit 1
fi

tr -d '\000' < "$URLS_JSON_FILE" | sed '1s/^\xEF\xBB\xBF//' > "$URLS_FILE"

if ! jq empty "$URLS_FILE" >/dev/null 2>&1; then
  echo "❌ JSON syntax invalid"
  jq empty "$URLS_FILE" 2>&1
  exit 1
fi

if ! jq -e 'has("urls") and (.urls | type == "array")' "$URLS_FILE" >/dev/null 2>&1; then
  echo "❌ JSON must contain a key 'urls' as an array"
  exit 1
fi

url_count=$(jq '.urls | length' "$URLS_FILE")
if [ "$url_count" -eq 0 ]; then
  echo "❌ No URLs found"
  exit 1
fi
echo "✅ Found $url_count URLs"

# ============================================
# Build payload JSON
# ============================================

PAYLOAD=$(jq -n \
  --arg process "github_action" \
  --arg project_name "$REPOSITORY_NAME" \
  --arg project_id "$REPOSITORY_ID" \
  --argjson setup "$SETUP" \
  --argjson teardown "$TEARDOWN" \
  '{
    process: $process,
    project: { name: $project_name, github_id: $project_id },
    options: { setup: $setup, teardown: $teardown }
  }'
)

# ============================================
# Launch scan via multipart/form-data
# ============================================

echo "🚀 Initiating scan..."
response=$(curl -s \
  -H "Authorization: Bearer $API_TOKEN" \
  -F "payload=$PAYLOAD;type=application/json" \
  -F "file=@$URLS_FILE;type=application/json" \
  "$API_POST_PROCESS")

jobId=$(echo "$response" | jq -r '.jobId // .taskId // empty')
if [ -z "${jobId:-}" ] || [ "$jobId" = "null" ]; then
  echo "❌ Failed to get jobId"
  echo "Response: $response"
  exit 1
fi

echo "✅ Scan initiated - Task ID: $jobId"

# ============================================
# Poll for job completion
# ============================================

max_attempts="${MAX_ATTEMPTS:-720}"
attempt=0
status="PENDING"

while [ "$status" != "COMPLETED" ] && [ "$status" != "FAILED" ]; do
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "❌ Timeout waiting for results"
    exit 1
  fi

  sleep "${POLL_INTERVAL:-5}"
  status_response=$(check_job_status "$jobId" "$API_TOKEN" || echo '{}')

  status=$(echo "$status_response" | jq -r '.status // .state // "unknown"')
  processed=$(echo "$status_response" | jq -r '.processedChunks // 0')
  total=$(echo "$status_response" | jq -r '.totalChunks // 0')

  echo "🔄 Status: $status | Processed: ${processed}/${total}"
  ((attempt++))
done

# ============================================
# Fetch and print results
# ============================================

if [ "$status" = "COMPLETED" ]; then
  echo "✅ Scan completed successfully"
  all_violations="[]"
  page=1
  limit=10

  while true; do
    page_response=$(fetch_status_page "$jobId" "$API_TOKEN" "$page" "$limit")
    page_violations=$(echo "$page_response" | jq '.scanData.violations // []')
    count_results=$(echo "$page_violations" | jq 'length')

    if [ "$count_results" -eq 0 ]; then
      break
    fi

    all_violations=$(echo "$all_violations" "$page_violations" | jq -s 'add')
    ((page++))
  done

  echo "--------------------------------------------"
  echo "📊 Violations summary:"
  echo "$all_violations" | jq -r '.[] | "\(.url): \((.results | map(.nodes | length) | add) // 0) violations"'

  report_uri=$(echo "$status_response" | jq -r '.scanData.reportUri // .reportUri // empty')
  if [ -n "$report_uri" ] && [ "$report_uri" != "null" ]; then
    echo "📄 Full Report: $report_uri"
  fi

  total_violations=$(echo "$all_violations" | jq '[.[] | .results | map(.nodes | length) | add] | add // 0')
  echo "📈 Total violations: $total_violations"

  if [ "$total_violations" -gt 0 ]; then
    echo "❌ Accessibility violations detected!"
    exit 0
  else
    echo "✅ No violations found!"
    exit 0
  fi
else
  echo "❌ Scan failed or timed out"
  exit 1
fi
