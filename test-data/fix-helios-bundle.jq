# =============================================================================
# fix_helios_bundle_all.jq
# Single-pass fix script for Helios FHIR R4 batch bundle
# Applies all 26 data quality fixes from original test-data.json
#
# Usage:
#   jq -f fix_helios_bundle_all.jq test-data.json > test-data-helios-fixed.json
#
# Verify:
#   jq '.entry | length' test-data-helios-fixed.json   # should be 813
# =============================================================================

# Fix 1: Add absolute fullUrl to all entries
.entry |= map(
  if has("fullUrl") then .
  elif (.resource.id != null) then
    . + {fullUrl: ("http://localhost:4004/hapi-fhir-jpaserver/fhir/" + .resource.resourceType + "/" + (.resource.id | tostring))}
  else . end
) |

# Fix 2: Remove meta.source #fragment references
walk(
  if type == "object" and
     .source? != null and (.source | type) == "string" and
     (.source | startswith("#")) then
    del(.source)
  else . end
) |

# Fix 3: Claim required R4 fields
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

# Fix 4: MedicationRequest.intent
.entry |= map(
  if .resource.resourceType == "MedicationRequest" and .resource.intent == null then
    .resource.intent = "order"
  else . end
) |

# Fix 5: Account.coverage.coverage
.entry |= map(
  if .resource.resourceType == "Account" and (.resource.coverage | type) == "array" then
    .resource.coverage |= map(
      if .coverage == null then . + {coverage: {"display": "Unknown"}} else . end)
  else . end
) |

# Fix 6: Family Planning invalid resource type in Encounter
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

# Fix 7: Remove patient-birthTime extensions with null valueDateTime
.entry |= map(
  if .resource != null and (.resource.extension | type) == "array" then
    .resource.extension |= map(select(
      type != "object" or
      (.url? | strings | contains("patient-birthTime") | not) or
      (.valueDateTime != null)
    ))
  else . end
) |

# Fix 8: ext-1 answerOption - remove extension when valueCoding also present
.entry |= map(
  if .resource != null then
    walk(
      if type == "object" and has("valueCoding") and has("extension") and
         (.url == null or (has("url") | not)) then
        del(.extension)
      else . end)
  else . end
) |

# Fix 9: Local/invalid coding systems
walk(
  if type == "object" and has("system") and has("code") then
    if .system == "Detected" or .system == "Normal" then
      .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
      .code = "unknown" |
      del(.display)
    elif .system == "www.cap.org/eCC" then
      .system = "urn:local:www.cap.org/eCC"
    else . end
  else . end
) |

# Fix 10: Null literal codes
walk(
  if type == "object" and (.code? | type) == "string" and .code == "null" then
    .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
    .code = "unknown"
  else . end
) |

# Fix 11: DL display name
walk(
  if type == "object" and
     .system? == "http://terminology.hl7.org/CodeSystem/v2-0203" and .code? == "DL" then
    del(.display)
  else . end
) |

# Fix 12: Remove all LOINC and SNOMED display names
walk(
  if type == "object" and .display? != null then
    if .system? == "http://loinc.org" or .system? == "http://snomed.info/sct" then
      del(.display)
    else . end
  else . end
) |

# Fix 13: J1100 trailing space
walk(if type == "string" and . == "J1100 " then "J1100" else . end) |

# Fix 14: issued date-only (DiagnosticReport and Observation only)
.entry |= map(
  if .resource.resourceType == "DiagnosticReport" or
     .resource.resourceType == "Observation" then
    .resource.issued |= (
      if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") then
        . + "T00:00:00Z"
      else . end)
  else . end
) |

# Fix 15: Posiive typo
walk(if type == "string" and contains("Posiive") then gsub("Posiive"; "Positive") else . end) |

# Fix 16: JMC system not a valid URI
walk(if type == "object" and .system? == "JMC system" then .system = "urn:local:JMC-system" else . end) |

# Fix 17: us-core-race/ethnicity wrong value type - convert to sub-extensions
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

# Fix 18: race/ethnicity wrong CodeSystem OID
walk(
  if type == "object" and
     (.system? == "http://terminology.hl7.org/CodeSystem/v3-Race" or
      .system? == "http://terminology.hl7.org/CodeSystem/v3-Ethnicity") then
    .system = "urn:oid:2.16.840.1.113883.6.238"
  else . end
) |

# Fix 19: us-core-2 Observation with no value or dataAbsentReason
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

# Fix 20: Specimen missing type
.entry |= map(
  if .resource.resourceType == "Specimen" and .resource.type == null then
    .resource.type = {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason", "code": "unknown"}]}
  else . end
) |

# Fix 21: Unknown LOINC codes (7+ digit numeric - not valid LOINC)
walk(
  if type == "object" and .system? == "http://loinc.org" and
     (.code? | strings | test("^[0-9]{7,}$")) then
    .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
    .code = "unknown"
  else . end
) |

# Fix 22: Unknown SNOMED codes
walk(
  if type == "object" and .system? == "http://snomed.info/sct" and
     (.code? | IN("36929009", "72300004", "433466002")) then
    .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
    .code = "unknown"
  else . end
) |

# Fix 23: Identifier.system not absolute URI
walk(
  if type == "object" and has("system") and has("value") and
     .system != null and (.system | type) == "string" and
     (.system | (startswith("http") or startswith("urn:") or startswith("oid:") or
      . == "phone" or . == "email" or . == "fax" or . == "url" or
      . == "sms" or . == "pager" or . == "other") | not) then
    .system = ("urn:local:" + .system)
  else . end
) |

# Fix 24: Remove unverifiable profiles
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

# Fix 25: Add narrative to resources missing it
.entry |= map(
  if .resource != null and (.resource | has("resourceType")) and
     (.resource.text == null or .resource.text.div == null) then
    .resource.text = {
      "status": "generated",
      "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>Narrative not available</p></div>"
    }
  else . end
) |

# Fix 26: Remove null issued and null extension fields (must be last)
# placed after all other fixes since some fixes can introduce null fields
walk(
  if type == "object" then
    (if has("issued") and .issued == null then del(.issued) else . end) |
    (if has("extension") and .extension == null then del(.extension) else . end)
  else . end
)
