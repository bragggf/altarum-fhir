.entry |= map(
  if has("fullUrl") then .
  elif (.resource.id != null) then
    . + {fullUrl: ("http://localhost:4004/hapi-fhir-jpaserver/fhir/" + .resource.resourceType + "/" + (.resource.id | tostring))}
  else . end
) |
walk(
  if type == "object" and
     .system? == "http://hl7.org/fhir/us/core/CodeSystem/condition-category" and
     .code? == "encounter-diagnosis" then
    .system = "http://terminology.hl7.org/CodeSystem/condition-category"
  else . end
) |
walk(
  if type == "object" and has("start") and has("end") and
     .start != null and .end != null and
     (.start | type) == "string" and (.end | type) == "string" and
     .start > .end then
    {start: .end, end: .start}
  else . end
) |
walk(if type == "string" and contains("Posiive") then gsub("Posiive"; "Positive") else . end) |
walk(
  if type == "object" and .url? != null and
     (.url | contains("us-core-birthsex")) and .valueCode? == "F " then
    .valueCode = "F"
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Specimen" and .resource.type == null then
    .resource.type = {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason", "code": "unknown"}]}
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
walk(
  if type == "object" and .system? == "http://snomed.info/sct" and
     .code? == "266919005" and .display? == "Never smoker" then
    .display = "Never smoked"
  else . end
) |
.entry |= map(
  if (.resource.meta.profile | type) == "array" then
    .resource.meta.profile |= map(select((contains("3.1.1") | not) and (contains("STU7") | not)))
  else . end
) |
.entry |= map(
  if .resource != null and (.resource | has("resourceType")) and
     (.resource.text == null or .resource.text.div == null) then
    .resource.text = {"status": "generated", "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>Narrative not available</p></div>"}
  else . end
)

