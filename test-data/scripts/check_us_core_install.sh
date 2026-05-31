#!/bin/bash

curl http://localhost:8080/fhir/StructureDefinition?url=http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient \
  | jq '.total'
# Should return 1 if installed correctly
