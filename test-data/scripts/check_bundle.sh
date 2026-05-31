#!/bin/bash

# Full pre-flight check before curl
BUNDLE_FILE="test-data.json"

echo "File size : $(wc -c < $BUNDLE_FILE) bytes"
echo "First 100 chars:"; head -c 100 $BUNDLE_FILE; echo

# Confirm it's a Bundle
RTYPE=$(jq -r '.resourceType' $BUNDLE_FILE 2>/dev/null)
echo "resourceType: $RTYPE"

ENTRIES=$(jq '.entry | length' $BUNDLE_FILE 2>/dev/null)
echo "Entry count : $ENTRIES"

# The cleaned file should NOT contain fhir_comments
jq '[.. | objects | select(has("fhir_comments"))] | length' ${BUNDLE_FILE} 
# Should return 0

# And should have fullUrls
jq '[.entry[] | select(has("fullUrl") | not)] | length' ${BUNDLE_FILE} 
# Should return 0

# Check entry counts differ
echo "Original : $(jq '.entry | length' ${BUNDLE_FILE})"
echo "Cleaned  : $(jq '.entry | length' clean_bundle_r4.json)"
