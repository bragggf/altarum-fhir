# Split into 200-entry batch chunks
#python3 split-bundle.py temp-data.json ./chunks/ 200

# Then load each chunk
FHIR_BASE=$1

for chunk in ./split_bundles/chunk_*.json; do
    echo "Loading $chunk..."
    HTTP_STATUS=$(curl -s -o /tmp/response.json -w "%{http_code}" \
        -X POST "$FHIR_BASE" \
        -H "Content-Type: application/fhir+json" \
        --max-time 300 \
        --data @"$chunk")
    
    ERRORS=$(jq '[.entry[]? | select(.response.status | startswith("4") or startswith("5"))] | length' /tmp/response.json 2>/dev/null || echo "?")
    echo "  HTTP $HTTP_STATUS | Errors: $ERRORS"
done
