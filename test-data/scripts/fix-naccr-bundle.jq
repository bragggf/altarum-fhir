

.entry |= map(
  if has("fullUrl") then .
  elif (.resource.id != null) then
    . + {fullUrl: (.resource.resourceType + "/" + (.resource.id | tostring))}
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
