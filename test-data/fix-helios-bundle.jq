walk(
  if type == "object" then
    (if has("issued") and .issued == null then del(.issued) else . end) |
    (if has("extension") and .extension == null then del(.extension) else . end)
  else . end
) |
walk(
  if type == "object" and has("system") and has("code") then
    if .system == "Detected" or .system == "Normal" then
      .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
      .code = "unknown"
    elif .system == "www.cap.org/eCC" then
      .system = "urn:local:www.cap.org/eCC"
    else . end
  else . end
) |
.entry |= map(
  if .resource != null and (.resource.extension | type) == "array" then
    .resource.extension |= map(select(
      type != "object" or
      (.url? | strings | contains("patient-birthTime") | not) or
      (.valueDateTime != null)
    ))
  else . end
) |
.entry |= map(
  if .resource != null then
    walk(
      if type == "object" and has("valueCoding") and has("extension") and
         (.url == null or (has("url") | not)) then
        del(.extension)
      else . end)
  else . end
) |
walk(
  if type == "object" and
     (.system? == "http://terminology.hl7.org/CodeSystem/v3-Race" or
      .system? == "http://terminology.hl7.org/CodeSystem/v3-Ethnicity") then
    .system = "urn:oid:2.16.840.1.113883.6.238"
  else . end
) |
walk(
  if type == "object" and .system? == "http://loinc.org" and
     (.code? | strings | test("^[0-9]{7,}$")) then
    .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
    .code = "unknown"
  else . end
) |
walk(
  if type == "object" and .system? == "http://snomed.info/sct" and
     (.code? | IN("36929009", "72300004", "433466002")) then
    .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
    .code = "unknown"
  else . end
) |
walk(
  if type == "object" and (.code? | type) == "string" and .code == "null" then
    .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
    .code = "unknown"
  else . end
) |
walk(
  if type == "object" and has("system") and has("value") and
     .system != null and (.system | type) == "string" and
     (.system | (startswith("http") or startswith("urn:") or startswith("oid:") or
      . == "phone" or . == "email" or . == "fax" or . == "url" or
      . == "sms" or . == "pager" or . == "other") | not) then
    .system = ("urn:local:" + .system)
  else . end
)

