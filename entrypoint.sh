#!/bin/bash

API_TOKEN="$1"
URLS="$2"

# Function to check job status
check_job_status() {
    local task_id="$1"
    local api_token="$2"
    
    curl -s -H "Authorization: Bearer $api_token" \
         -H "Content-Type: application/json" \
         "https://beep-beep-67490882d6fc.herokuapp.com/v1/engine/axe/$task_id"
}

# Convert comma-separated URLs to array
IFS=',' read -ra URL_ARRAY <<< "$URLS"

# Process each URL
for url in "${URL_ARRAY[@]}"; do
    echo "📋 Initiating scan for URL: $url"
    
    # Submit the job
    response=$(curl -s -H "Authorization: Bearer $API_TOKEN" \
                    -H "Content-Type: application/json" \
                    -X POST \
                    -d "{\"url\": \"$url\"}" \
                    "https://beep-beep-67490882d6fc.herokuapp.com/v1/engine/axe")
    
    # Extract task_id from response
    task_id=$(echo $response | jq -r '.task_id')
    
    if [ -z "$task_id" ] || [ "$task_id" == "null" ]; then
        echo "❌ Failed to get task_id for $url"
        echo "Response: $response"
        continue
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
        sleep 10
        
        # Check status
        status_response=$(check_job_status "$task_id" "$API_TOKEN")
        status=$(echo $status_response | jq -r '.status')
        message=$(echo $status_response | jq -r '.message')
        
        echo "🔄 Status: $status - $message"
        
        ((attempt++))
    done
    
    # Process final results
    if [ "$status" == "completed" ]; then
        echo "✅ Scan completed successfully"
        results=$(echo $status_response | jq '.results')
        
        # Set output for GitHub Actions
        echo "::set-output name=scan_results::$results"
        
        # You can process results further here
        # For example, count violations
        violation_count=$(echo $results | jq '.violations | length')
        echo "Found $violation_count accessibility violations"
        
        # Optional: Print detailed violations
        echo $results | jq '.violations[] | {impact: .impact, description: .description}'
    else
        echo "❌ Scan failed or timed out"
        echo "Final status: $status"
        echo "Final message: $message"
    fi
    
    echo "-----------------------------------"
done