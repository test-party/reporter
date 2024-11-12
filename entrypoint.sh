#!/bin/bash

API_TOKEN="$1"
REPOSITORY_NAME="$2"
URLS="$3"
AUTH_TYPE="$4"
AUTH_URL="$5"
AUTH_EMAIL="$6"
AUTH_PASSWORD="$7"

# Function to check job status
check_job_status() {
    local task_id="$1"
    local api_token="$2"
    
    curl -s \
         -H "Content-Type: application/json" \
         "https://beep-beep-67490882d6fc.herokuapp.com/v1/engine/axe/$task_id"
}

# Convert comma-separated URLs to JSON array
URL_JSON_ARRAY=$(echo $URLS | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')

# Prepare authentication JSON if credentials are provided
AUTH_JSON=""
if [ ! -z "$AUTH_EMAIL" ] && [ ! -z "$AUTH_PASSWORD" ]; then
    AUTH_JSON=", \"auth\": {\"url\": \"$AUTH_URL\", \"email\": \"$AUTH_EMAIL\", \"password\": \"$AUTH_PASSWORD\"}"
fi

# Prepare request body
REQUEST_BODY="{\"urls\": $URL_JSON_ARRAY, \"options\": {$AUTH_JSON}, \"process\": \"github_action\", \"project_name\": \"$REPOSITORY_NAME\"}"

# Debug: Print the request body (optional)
echo "Request Body: $REQUEST_BODY"

echo "📋 Initiating scan for multiple URLs"

# Submit the job
response=$(curl -s -H "Authorization: Bearer $API_TOKEN" \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$REQUEST_BODY" \
                "https://beep-beep-67490882d6fc.herokuapp.com/v1/engine/axe")
    
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
max_attempts=30  # Maximum number of polling attempts
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
Found \(.results | length) violations

Detailed Violations:
\(.results | .[] | "
Impact: \(.impact)
Rule: \(.id)
Description: \(.description)
Elements Affected: \(.nodes | length)
---")"'

    # Summary of violations by URL
    echo "📊 Summary by URL:"
    echo $results | jq -r '.violations[] | "\(.url): \(.results | length) violations"'

    report_uri=$(echo $results | jq -r '.reportUri')
    echo "📄 Report URL: $report_uri"

    # Total violation count across all URLs
    total_violations=$(echo $results | jq '[.violations[].results | length] | add')
    echo "📈 Total violations across all URLs: $total_violations"

    # Group violations by impact across all URLs
    # echo "🎯 Violations by Impact Level:"
    # echo $results | jq -r '
    #     [.violations[].results[].impact] | 
    #     group_by(.) | 
    #     map({impact: .[0], count: length}) | 
    #     .[] | 
    #     "[\(.impact)] Count: \(.count)"
    # '
else
    echo "❌ Scan failed or timed out"
    echo "Final status: $status"
    echo "Final message: $message"
fi