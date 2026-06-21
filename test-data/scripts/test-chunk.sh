#!/bin/bash

curl -s -X POST \
  http://localhost:4004/hapi-fhir-jpaserver/fhir \
  -H "Content-Type: application/fhir+json" \
  -o response.json -w "%{http_code}" \
  --data @split_bundles/chunk_0001_of_0133.json

cat response.json | python3 -m json.tool | grep -A3 "diagnostics"

