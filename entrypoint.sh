#!/bin/bash

API_TOKEN="$1"
REPOSITORY_NAME="$2"
REPOSITORY_ID="$3"
URLS="$4"
SETUP="$5"
TEARDOWN="$6"

# Function to check job status
check_job_status() {
    local task_id="$1"
    local api_token="$2"
    
    curl -s \
         -H "Content-Type: application/json" \
         "https://api.testparty.ai/v1/scan/status/$task_id"
}

# Prepare request body
OPTIONS="{\"setup\": $SETUP, \"teardown\": $TEARDOWN}"
REQUEST_BODY="{\"urls\": $URLS, \"process\": \"github_action\", \"project\": {\"name\": \"$REPOSITORY_NAME\", \"github_id\": $REPOSITORY_ID}, \"options\": $OPTIONS}"

# Debug: Print the request body (optional)
echo "Request Body: $REQUEST_BODY"

echo "📋 Initiating scan for multiple URLs"

# Submit the job
response=$(curl -s -H "Authorization: Bearer $API_TOKEN" \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$REQUEST_BODY" \
                "https://api.testparty.ai/v1/scan")
    
# Extract task_id from response
task_id=$(echo $response | jq -r '.task_id')

if [ -z "$task_id" ] || [ "$task_id" == "null" ]; then
    echo "❌ Failed to get task_id for $url"
    echo "Response: $response"
    exit 1
fi

echo "✅ Scan initiated - Task ID: $task_id"

# Poll for results
status="PENDING"
max_attempts=720  # Maximum number of polling attempts is 1 hour (5 seconds * 720 attempts)
attempt=0

while [ "$status" != "completed" ] && [ "$status" != "failed" ]; do
    if [ $attempt -ge $max_attempts ]; then
        echo "❌ Timeout waiting for results"
        break
    fi
    
    # Wait between polls
    sleep 5
    
    # Check status
    status_response=$(check_job_status "$task_id" "$API_TOKEN")
    status=$(echo $status_response | jq -r '.state')
    message=$(echo $status_response | jq -r '.message')
    
    echo "🔄 Status: $status - $message"
    
    ((attempt++))
done

# Process final results
if [ "$status" == "completed" ]; then
    echo "✅ Scan completed successfully"
    results=$(echo $status_response | jq '.results')
    
    # Process each URL's violations
    echo $results | jq -r '.violations[] | "
🔍 URL: \(.url)
Found \((.results | length) // 0) violations

Detailed Violations:
\(.results | .[] | "
Impact: \(.impact)
Rule: \(.id)
Description: \(.description)
Elements Affected: \(.nodes | length)
---")"'

    # Summary of violations by URL
    echo "📊 Summary by URL:"
    echo $results | jq -r '.violations[] | "\(.url): \((.results | map(.nodes | length) | add) // 0) violations"'

    report_uri=$(echo $results | jq -r '.reportUri')
    echo "📄 Report URL: $report_uri"

    # Total violation count across all URLs
    total_violations=$(echo $results | jq '([.violations[].results | map(.nodes | length) | add] | add) // 0')
    echo "📈 Total violations across all URLs: $total_violations"
else
    echo "❌ Scan failed or timed out"
    echo "Final status: $status"
    echo "Final message: $message"
fi