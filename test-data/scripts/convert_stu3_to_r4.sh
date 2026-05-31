#!/bin/bash

FHIR_BASE_URL="http://localhost:8080/fhir" 

jq '
  .entry |= map(
    # ExplanationOfBenefit required R4 fields
    if .resource.resourceType == "ExplanationOfBenefit" then
      .resource |=
        (if .use == null then .use = "claim" else . end) |
        (if .outcome == null then .outcome = "complete" else . end) |
        (if .created == null then .created = "1970-01-01T00:00:00Z" else . end) |
        (if .provider == null then .provider = {"display": "Unknown"} else . end) |
        (if .insurer == null then .insurer = {"display": "Unknown"} else . end) |
        (.insurance |= map(if .focal == null then .focal = true else . end)) |
        (.total |= if . then map(if .amount == null then .amount = {"value": 0, "currency": "USD"} else . end) else . end)

    # Claim required R4 fields
    elif .resource.resourceType == "Claim" then
      .resource |=
        (if .priority == null then .priority = {"coding": [{"code": "normal"}]} else . end) |
        (if .created == null then .created = "1970-01-01T00:00:00Z" else . end) |
        (if .provider == null then .provider = {"display": "Unknown"} else . end) |
        (.item |= if . then map(if .productOrService == null then .productOrService = {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason","code": "unknown"}]} else . end) else . end)

    # Coverage required status
    elif .resource.resourceType == "Coverage" then
      .resource |=
        (if .status == null then .status = "active" else . end) |
        (if .payor == null then .payor = [{"display": "Unknown"}] else . end)

    # MedicationRequest required R4 fields
    elif .resource.resourceType == "MedicationRequest" then
      .resource |=
        (if .status == null then .status = "active" else . end) |
        (if .intent == null then .intent = "order" else . end) |
        (if .medicationCodeableConcept == null and .medicationReference == null then
          .medicationCodeableConcept = {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason","code": "unknown"}]}
        else . end)

    # Procedure required R4 fields
    elif .resource.resourceType == "Procedure" then
      .resource |=
        (if .status == null then .status = "unknown" else . end)

    # Condition - fix CodeSystem URLs and con-4 constraint
    elif .resource.resourceType == "Condition" then
      .resource |=
        (if .clinicalStatus.coding then
          .clinicalStatus.coding |= map(.system = "http://terminology.hl7.org/CodeSystem/condition-clinical")
        else . end) |
        (if .verificationStatus.coding then
          .verificationStatus.coding |= map(.system = "http://terminology.hl7.org/CodeSystem/condition-ver-status")
        else . end) |
        (if .abatement != null then
          .clinicalStatus.coding[0].code = "resolved"
        else . end)

    else . end
  ) |

  # Strip mihin copyright extensions from all resources
  walk(
    if type == "array" then
      map(select(type != "object" or .url? != "http://mihin.org/extension/copyright"))
    else . end
  )
' clean_bundle_5.json > clean_bundle_r4.json

