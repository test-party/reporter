#!/bin/bash
set -euo pipefail
# trap 'echo "❌ Error at line $LINENO: Command exited with status $?"' ERR
# ============================================
# Usage:
# ./run_scan.sh <API_TOKEN> <REPOSITORY_NAME> <REPOSITORY_ID> <URLS_JSON_FILE> <SETUP_JSON> <TEARDOWN_JSON>
# ============================================

API_TOKEN="$1"
REPOSITORY_NAME="$2"
REPOSITORY_ID="$3"
URLS="$4"
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
# ============================================
# Validate and prepare URLs
# ============================================
URLS_FILE="/tmp/urls_clean.json"

if [ -z "${URLS:-}" ]; then
    echo "❌ URLs input is required (file path or JSON string)"
    exit 1
fi

# Check if URLS is a file or a JSON string
if [ -f "$URLS" ]; then
    # It's a file
    echo "📄 Using URLs from file: $URLS"
    
    file_size=$(stat -c%s "$URLS" 2>/dev/null || stat -f%z "$URLS" 2>/dev/null)
    file_size_kb=$((file_size / 1024))
    echo "📊 File size: ${file_size_kb} KB ($file_size bytes)"
    
    open_braces=$(grep -o '{' "$URLS" | wc -l | tr -d ' ')
    close_braces=$(grep -o '}' "$URLS" | wc -l | tr -d ' ')
    open_brackets=$(grep -o '\[' "$URLS" | wc -l | tr -d ' ')
    close_brackets=$(grep -o '\]' "$URLS" | wc -l | tr -d ' ')
    
    if [ "$open_braces" -ne "$close_braces" ] || [ "$open_brackets" -ne "$close_brackets" ]; then
        echo "❌ Invalid JSON structure (unbalanced braces/brackets)"
        exit 1
    fi
    
    tr -d '\000' < "$URLS" | sed '1s/^\xEF\xBB\xBF//' > "$URLS_FILE"
else
    # It's a JSON string
    echo "📝 Using URLs from parameter string"
    
    # Create a temporary JSON file with the URLs array wrapped
    echo "$URLS" > /tmp/urls_raw.json
    
    # Check if the input already has the "urls" wrapper
    if echo "$URLS" | jq -e 'has("urls")' >/dev/null 2>&1; then
        # Already has "urls" key
        echo "$URLS" | jq '.' > "$URLS_FILE"
    else
        # Wrap the array with "urls" key
        echo "$URLS" | jq '{urls: .}' > "$URLS_FILE"
    fi
fi

# Validate JSON syntax
if ! jq empty "$URLS_FILE" >/dev/null 2>&1; then
    echo "❌ JSON syntax invalid"
    jq empty "$URLS_FILE" 2>&1
    exit 1
fi

# Ensure "urls" key exists
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
  --arg schedule_type "automated" \
  --arg origin_platform "github_action" \
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
attempt=1
status="PENDING"

while [ "$status" != "COMPLETED" ] && [ "$status" != "FAILED" ]; do
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "❌ Timeout waiting for results"
    exit 1
  fi
  
  status_response=$(check_job_status "$jobId" "$API_TOKEN")
  
  status=$(echo "$status_response" | jq -r '.status // .state // "unknown"')
  processed=$(echo "$status_response" | jq -r '.processedChunks // 0')
  total=$(echo "$status_response" | jq -r '.totalChunks // 0')

  echo "🔄 Status: $status | Processed: ${processed}/${total}"
  
  if [ "$status" = "COMPLETED" ] || [ "$status" = "FAILED" ]; then
    break
  fi
  
  ((attempt++))
  sleep "${POLL_INTERVAL:-5}"
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
    echo "📄 Full Report: $report_uri"
  fi

  # Total violations
  total_violations=$(echo "$all_violations" | jq '[.[] | .results | map(.nodes | length) | add] | add // 0')
  echo "--------------------------------------------"
  echo "📈 Total violations across all URLs: $total_violations"
  echo "--------------------------------------------"

  # Exit with error if violations found
  if [ "$total_violations" -gt 0 ]; then
    echo "❌ Accessibility violations detected!"
    exit 0
  else
    echo "✅ No accessibility violations found!"
    exit 0
  fi

else
  echo "❌ Scan failed or timed out"
  echo "Final status: $status"
  msg=$(echo "$status_response" | jq -r '.message // .msg // empty' 2>/dev/null || echo "")
  if [ -n "$msg" ]; then
    echo "Message: $msg"
  fi
  exit 1
fi