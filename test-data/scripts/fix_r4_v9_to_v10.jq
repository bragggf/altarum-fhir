walk(if type == "object" and .system? == "http://unitsofmeasure.org" and .code? == "{L}/min" then .code = "L/min" else . end) |
walk(if type == "object" and .code? == "TBC" and (.system? == null or .system? == "") then .system = "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation" | .code = "U" | .display = "Unknown" else . end) |
walk(if type == "object" and .code? == "Crowe" then .system = "http://terminology.hl7.org/CodeSystem/v2-0203" | .code = "U" | .display = "Unspecified identifier" else . end) |
walk(if type == "object" and .system? == "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation" and (.code? == "TBC" or .code? == "TPN") then .code = "U" | .display = "Unknown" else . end) |
.entry |= map(if .resource.resourceType == "Observation" and (.resource.code.coding // [] | map(select(.system? | strings | contains("loinc.org"))) | length) > 0 and ((.resource.category // []) | map(select((.coding // []) | map(select(.code? == "laboratory")) | length > 0)) | length) == 0 then .resource.category = ((.resource.category // []) + [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/observation-category","code": "laboratory","display": "Laboratory"}]}]) else . end) |
.entry |= map(if .resource.resourceType == "Observation" and .resource.dataAbsentReason != null and (.resource.valueQuantity != null or .resource.valueCodeableConcept != null or .resource.valueString != null) then .resource |= del(.dataAbsentReason) else . end) |
walk(if type == "object" and has("time") and .time == null then del(.time) else . end)


