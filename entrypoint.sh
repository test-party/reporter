#!/bin/bash
set -euo pipefail

# Input arguments
API_TOKEN="$1"
REPOSITORY_NAME="$2"
REPOSITORY_ID="$3"
URLS="$4"
SETUP="$5"
TEARDOWN="$6"

# API endpoints
API_POST_PROCESS="https://2a930ibq5j.execute-api.us-east-2.amazonaws.com/Stage/process"
API_BASE_STATUS="https://2a930ibq5j.execute-api.us-east-2.amazonaws.com/Stage/status"

# Function: check the status of a job by jobId
check_job_status() {
  local jobId="$1"
  local token="$2"
  curl -s \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "$API_BASE_STATUS/$jobId"
}

# Function: fetch a specific page of job results
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

# Build request payload
OPTIONS="{\"setup\": $SETUP, \"teardown\": $TEARDOWN}"
REQUEST_BODY="{\"urls\": $URLS, \"process\": \"github_action\", \"project\": {\"name\": \"$REPOSITORY_NAME\", \"github_id\": $REPOSITORY_ID}, \"options\": $OPTIONS}"

echo "Request Body: $REQUEST_BODY"
echo "📋 Initiating scan for URLs"

# Start the scan
response=$(curl -s -H "Authorization: Bearer $API_TOKEN" \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$REQUEST_BODY" \
                "$API_POST_PROCESS")

# Extract jobId from response
jobId=$(echo "$response" | jq -r '.jobId')
if [ -z "${jobId:-}" ] || [ "$jobId" = "null" ]; then
  echo "❌ Failed to get jobId"
  echo "Response: $response"
  exit 1
fi
echo "✅ Scan initiated - Task ID: $jobId"

# Polling variables
status="pending"
max_attempts=720  # 720 * 5s = 1 hour max wait
attempt=0

# Poll job status until completion or timeout
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
  curr_page=$(echo "$status_response" | jq -r '.pagination.currentPage // 0')
  total_pages=$(echo "$status_response" | jq -r '.pagination.totalPages // 0')
  msg=$(echo "$status_response" | jq -r '.message // ""')

  echo "🔄 Status: ${status:-unknown} | Chunks ${processed}/${total} | Page ${curr_page}/${total_pages} ${msg:+| $msg}"

  if [ "$status" = "completed" ] || [ "$status" = "failed" ]; then
    break
  fi

  ((attempt++))
done

# Process final results
if [ "$status" = "completed" ]; then
  echo "✅ Scan completed successfully"
  
  # Fetch results from all pages
  all_violations="[]"
  page=1
  limit=100
  
  # Extract total_pages from last status response
  total_pages=$(echo "$status_response" | jq -r '.pagination.totalPages // 1')
  
  while [ $page -le $total_pages ]; do
    echo "🔍 Fetching page $page of $total_pages..."
    
    if [ $page -eq 1 ]; then
      # Reuse the first response for page 1
      page_response="$status_response"
    else
      # Fetch additional pages
      page_response=$(fetch_status_page "$jobId" "$API_TOKEN" "$page" "$limit")
    fi
    
    # Extract violations from this page
    page_violations=$(echo "$page_response" | jq '.scanData.violations // []')
    
    echo "🔍 Page $page violations found: $(echo "$page_violations" | jq 'length')"
    
    # Merge violations across all pages
    all_violations=$(echo "$all_violations $page_violations" | jq -s 'add')
    
    ((page++))
  done
  
  echo "🔍 Total violations from all pages: $(echo "$all_violations" | jq 'length')"
  
  # Print detailed results for each URL
  echo "$all_violations" | jq -r '
    .[] as $urlData |
    "🔍 URL: \($urlData.url)
Found \($urlData.results | map(.nodes | length) | add // 0) violations

Detailed Violations:
\($urlData.results[] |
  "Impact: \(.impact)
Rule: \(.id)
Description: \(.description)
Elements Affected: \(.nodes | length)
---")"
  '

  # Print summary of violations by URL
  echo "📊 Summary by URL:"
  echo "$all_violations" | jq -r '.[] | "\(.url): \((.results | map(.nodes | length) | add) // 0) violations"'

  # Print report URI if available
  report_uri=$(echo "$status_response" | jq -r '.scanData.reportUri // .reportUri // empty')
  if [ -n "$report_uri" ] && [ "$report_uri" != "null" ]; then
    echo "📄 Report URL: $report_uri"
  fi

  # Print total violations across all URLs
  total_violations=$(echo "$all_violations" | jq '[.[] | .results | map(.nodes | length) | add] | add // 0')
  echo "📈 Total violations across all URLs: $total_violations"
  
else
  echo "❌ Scan failed or timed out"
  echo "Final status: $status"
  if [ -n "${msg:-}" ]; then
    echo "Final message: $msg"
  fi
fi
