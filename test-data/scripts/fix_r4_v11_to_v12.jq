.entry |= map(
  if .resource.resourceType == "MedicationRequest" and
     (.resource.requester != null) and (.resource.requester.reference != null) and
     (.resource.requester.reference | startswith("PractitionerRole/")) then
    .resource.requester = {"display": "Unknown"}
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
  .resource.extension |= (
    if type == "array" then
      map(select((.url? | strings | startswith("http://example.com")) | not))
    else . end)
) |
.entry |= map(
  if .resource.resourceType == "Observation" and
     (.resource.valueQuantity?.value? != null) and
     (.resource.valueQuantity.value | type) == "number" and
     .resource.valueQuantity.value > 0 and .resource.valueQuantity.value < 1 then
    if (.resource.meta.profile | type) == "array" then
      .resource.meta.profile |= map(select(contains("observation-lab") | not))
    else . end
  else . end
) |
walk(if type == "object" and has("time") and .time == null then del(.time) else . end) |
.entry |= map(
  if .resource.resourceType == "Observation" and
     .resource.dataAbsentReason != null and
     (.resource.valueQuantity != null or .resource.valueCodeableConcept != null or .resource.valueString != null) then
    .resource |= del(.dataAbsentReason)
  else . end
)

