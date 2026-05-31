.entry |= map(
  if .resource.resourceType == "Observation" and
     (.resource.valueTime != null) and
     (.resource.valueTime | type) == "string" and
     (.resource.valueTime | test("^[0-9]{6}$")) then
    .resource.valueTime = (.resource.valueTime | .[0:2] + ":" + .[2:4] + ":" + .[4:6])
  else . end
) |
walk(
  if type == "array" then
    map(select(type != "object" or (.valuePositiveInt? != 0)))
  else . end
)

