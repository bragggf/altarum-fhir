#!/bin/bash

FHIR_BASE_URL="http://localhost:8080/fhir" 

#jq 'walk(if type == "object" then del(.fhir_comments) else . end)' test-data.json > clean_bundle.json #jq 'walk( #  if type == "object" then
#    del(.fhir_comments) |
#    if . == {} then empty else . end
#  elif type == "array" then
#    map(select(. != {}))
#  else .
#  end
#)' test-data.json > clean_bundle.json


jq '
  # Step 1: remove fhir_comments from every object
  walk(if type == "object" then del(.fhir_comments) else . end) |

  # Step 2: remove empty objects only from known array fields
  .entry |= map(select(. != null and .resource != null)) |
  .entry[].resource |= with_entries(select(.value != null and .value != {} and .value != []))
' original-test-data.json > clean_bundle_1.json

# Find entries with no resourceType
echo "jq quiery for entries having a null resource type. should be 0"
jq '[.entry[] | select(.resource.resourceType == null or .resource == null)]' clean_bundle_1.json


### cleaning URL entries
#jq '
#  .entry |= map(
#    if has("fullUrl") then .
#    elif .resource.id then
#      . + {fullUrl: (.resource.resourceType + "/" + .resource.id)}
#    else .
#    end
#  )
#' clean_bundle3.json > clean_bundle4.json

# another script to fix URL entries. disable this
#jq '
#  .entry |= map(
#    if has("fullUrl") then .
#    elif .resource.id then
#      . + {fullUrl: ("urn:uuid:" + .resource.id)}
#    else .
#    end
#  )
#' clean_bundle_1.json > clean_bundle_2.json


jq --arg base "$FHIR_BASE_URL" '
  .entry |= map(
    # Fix fullUrl — must be absolute
    (if has("fullUrl") then .
     elif .resource.id then
       . + {fullUrl: ("urn:uuid:" + .resource.id)}
     else . end) |

    # Fix request.url — must be relative
    if .request.url and (.request.url | startswith("http")) then
      .request.url |= (split("/") | .[-2:] | join("/"))
    else .
    end
  )
' clean_bundle_1.json > clean_bundle_2.json

cp clean_bundle_2.json clean_bundle.json
rm test-data.json
ln -s clean_bundle.json test-data.json

# Count total entries before and after cleaning
jq '.entry | length' original-test-data.json
jq '.entry | length' test-data.json


