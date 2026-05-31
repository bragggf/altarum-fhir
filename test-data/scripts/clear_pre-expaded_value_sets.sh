#!/bin/bash

# Clear stale pre-expanded ValueSets from the database
curl -s -X POST "http://localhost:8080/fhir/\$expunge" \
  -H "Content-Type: application/fhir+json" \
  -d '{"resourceType":"Parameters","parameter":[{"name":"expungeEverything","valueBoolean":true}]}'
