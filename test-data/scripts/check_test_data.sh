#!/bin/bash

# Check no fhir_comments remain
jq '[.. | objects | select(has("fhir_comments"))] | length' test-data.json

# Check no empty objects remain
jq '[.. | objects | select(. == {})] | length' test-data.json

# Find entries with no resourceType
jq '[.entry[] | select(.resource.resourceType == null or .resource == null)]' test-data.json

# Count total entries before and after cleaning
jq '.entry | length' clean_bundle.json
jq '.entry | length' test-data.json

