.entry |= map(
  if .resource.resourceType == "Patient" and
     .resource.id == "b2d6043c-4388-407d-b7af-469892988a63" then
    .resource.extension |= map(
      if .url == "http://hl7.org/fhir/StructureDefinition/patient-birthPlace" and
         .valueAddress._district != null then
        .valueAddress |= del(._district)
      else . end)
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Patient" and
     .resource.id == "ac6b87c7-d2ea-4043-a583-1ee91bc17aed" then
    (.resource.address[0] |= del(._city)) |
    (.resource.address[0] |= del(._district))
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Observation" and
     .resource.id == "042f1f58-ad0f-478e-8ac8-4d4f0c4a31c3" then
    .resource |= del(.dataAbsentReason)
  else . end
) |
.entry |= map(
  if .resource.resourceType == "Patient" and
     .resource.id == "b2d6043c-4388-407d-b7af-469892988a63" then
    .resource |= del(._multipleBirthBoolean)
  else . end
)

