chmod +x entrypoint.sh

#!/bin/bash

# Ler URLs do arquivo JSON
URLS=$(cat urls-nano.json| jq -c '.urls')

./entrypoint.sh \
  "4c09596b-fe3d-489c-9bb6-b24cd9d6df26" \
  "test-party/reporter" \
  "886868479" \
  "$URLS" \
  '[]' \
  '[]'