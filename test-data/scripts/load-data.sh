#!/bin/bash

for f in *.json; do
  curl -X POST http://localhost:8080/fhir \
       -H "Content-Type: application/fhir+json" \
       -d @"$f"
done

