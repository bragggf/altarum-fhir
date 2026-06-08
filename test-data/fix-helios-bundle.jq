.entry |= map(
  if has("fullUrl") then .
  elif (.resource.id != null) then
    . + {fullUrl: ("http://localhost:4004/hapi-fhir-jpaserver/fhir/" + .resource.resourceType + "/" + (.resource.id | tostring))}
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Claim" then
    .resource |= (. + {
      created:  (.created  // "1970-01-01T00:00:00Z"),
      priority: (.priority // {"coding": [{"code": "normal"}]})
    }) |
    (if (.resource.insurance | type) == "array" then
      .resource.insurance |= map(. + {focal: (.focal // true)})
    else . end) |
    (if (.resource.procedure | type) == "array" then
      .resource.procedure |= map(
        if .procedureCodeableConcept == null and .procedureReference == null then
          . + {procedureCodeableConcept: {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason", "code": "unknown"}]}}
        else . end)
    else . end)
  else . end
) |
.entry |= map(
  if .resource.resourceType == "MedicationRequest" and .resource.intent == null then
    .resource.intent = "order"
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Account" and
     (.resource.coverage | type) == "array" then
    .resource.coverage |= map(
      if .coverage == null then . + {coverage: {"display": "Unknown"}} else . end)
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Encounter" then
    (if .resource.class.display? == "Family Planning" then
      .resource.class = {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "AMB", "display": "ambulatory"}
    else . end) |
    (if .resource.subject.type? == "Family Planning" then
      .resource.subject |= del(.type)
    else . end)
  else . end
) |
walk(
  if type == "object" and .code? == "null" and .system? != null then
    .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
    .code = "unknown"
  else . end
) |
walk(
  if type == "object" and
     .system? == "http://terminology.hl7.org/CodeSystem/v2-0203" and
     .code? == "DL" then
    del(.display)
  else . end
) |
walk(
  if type == "object" and .display? != null then
    if .system? == "http://loinc.org" or .system? == "http://snomed.info/sct" then
      del(.display)
    else . end
  else . end
) |
walk(if type == "string" and . == "J1100 " then "J1100" else . end) |
.entry |= map(
  .resource.issued |= (
    if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") then
      . + "T00:00:00Z"
    else . end)
) |
walk(if type == "string" and contains("Posiive") then gsub("Posiive"; "Positive") else . end) |
walk(
  if type == "object" and .system? == "JMC system" then
    .system = "urn:local:JMC-system"
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Patient" then
    .resource.extension |= (
      if type == "array" then
        map(
          if (.url | contains("us-core-race")) and .valueCodeableConcept != null then
            {"url": .url, "extension": ([{"url": "ombCategory", "valueCoding": .valueCodeableConcept.coding[0]}, {"url": "text", "valueString": (.valueCodeableConcept.text // .valueCodeableConcept.coding[0].display // "Unknown")}] | map(select(.valueCoding != null or .valueString != null)))}
          elif (.url | contains("us-core-ethnicity")) and .valueCodeableConcept != null then
            {"url": .url, "extension": ([{"url": "ombCategory", "valueCoding": .valueCodeableConcept.coding[0]}, {"url": "text", "valueString": (.valueCodeableConcept.text // .valueCodeableConcept.coding[0].display // "Unknown")}] | map(select(.valueCoding != null or .valueString != null)))}
          else . end)
      else . end)
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Observation" and
     .resource.valueQuantity == null and .resource.valueCodeableConcept == null and
     .resource.valueString == null and .resource.valueBoolean == null and
     .resource.valueInteger == null and .resource.dataAbsentReason == null and
     (.resource.component == null or (.resource.component | length) == 0) and
     (.resource.hasMember == null or (.resource.hasMember | length) == 0) then
    .resource.dataAbsentReason = {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason", "code": "unknown", "display": "Unknown"}]}
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Specimen" and .resource.type == null then
    .resource.type = {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason", "code": "unknown"}]}
  else . end
) |
.entry |= map(
  if (.resource.meta.profile | type) == "array" then
    .resource.meta.profile |= map(
      select(
        (contains("cancer-reporting") | not) and
        (contains("sdc-") | not) and
        (contains("sdoh") | not) and
        (contains("3.1.1") | not) and
        (contains("STU7") | not)))
  else . end
) |
.entry |= map(
  if .resource != null and (.resource | has("resourceType")) and
     (.resource.text == null or .resource.text.div == null) then
    .resource.text = {"status": "generated", "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>Narrative not available</p></div>"}
  else . end
)

