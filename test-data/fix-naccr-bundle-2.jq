.entry |= map(
  if has("fullUrl") then
    if (.fullUrl | startswith("http") | not) and (.fullUrl | startswith("urn:") | not) then
      .fullUrl = ("http://localhost:4004/hapi-fhir-jpaserver/fhir/" + .fullUrl)
    else . end
  elif (.resource.id != null) then
    . + {fullUrl: ("http://localhost:4004/hapi-fhir-jpaserver/fhir/" + .resource.resourceType + "/" + (.resource.id | tostring))}
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Condition" and
     (.resource.asserter != null) and (.resource.asserter.reference != null) and
     (.resource.asserter.reference | startswith("PractitionerRole/")) then
    .resource.asserter = {"display": "Unknown"}
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Observation" and
     (.resource.performer | type) == "array" then
    .resource.performer |= map(
      if (.reference != null) and (.reference | startswith("PractitionerRole/")) then
        {"display": "Unknown"}
      else . end)
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Encounter" and
     (.resource.participant | type) == "array" then
    .resource.participant |= map(
      if (.individual != null) and (.individual.reference != null) and
         (.individual.reference | startswith("PractitionerRole/")) then
        .individual = {"display": "Unknown"}
      else . end)
  else . end
) |
.entry |= map(
  if .resource.resourceType == "MedicationRequest" and
     (.resource.requester != null) and (.resource.requester.reference != null) and
     (.resource.requester.reference | startswith("PractitionerRole/")) then
    .resource.requester = {"display": "Unknown"}
  else . end
) |
.entry |= map(
  if .resource.resourceType == "MedicationAdministration" and
     (.resource.performer | type) == "array" then
    .resource.performer |= map(
      if (.actor != null) and (.actor.reference != null) and
         (.actor.reference | startswith("PractitionerRole/")) then
        .actor = {"display": "Unknown"}
      else . end)
  else . end
) |
walk(
  if type == "object" and
     .system? == "http://terminology.hl7.org/CodeSystem/condition-clinical" and
     .code? == "Active" then
    .code = "active"
  else . end
) |
.entry |= map(
  if .resource != null and (.resource | has("resourceType")) and
     (.resource.text == null or .resource.text.div == null) then
    .resource.text = {
      "status": "generated",
      "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>Narrative not available</p></div>"
    }
  else . end
)

