chmod +x entrypoint.sh

#!/bin/bash

# Read JSON urls
URLS=$(cat urls.json| jq -c '.urls')

./entrypoint.sh \
  "4c09596b-fe3d-489c-9bb6-b24cd9d6df26" \
  "test-party/guinea-pig-iframe" \
  "1011482448" \
  "$URLS" \
  '[]' \
  '[]'