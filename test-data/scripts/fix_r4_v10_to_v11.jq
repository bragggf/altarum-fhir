# Fix 1: PractitionerRole in Condition.asserter
.entry |= map(
  if .resource.resourceType == "Condition" and
     (.resource.asserter != null) and
     (.resource.asserter | type) == "object" and
     (.resource.asserter.reference != null) and
     (.resource.asserter.reference | startswith("PractitionerRole/")) then
    .resource.asserter = {"display": "Unknown"}
  else . end
) |

# Fix 2: PractitionerRole in MedicationAdministration.performer
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

# Fix 3: Remove display from v3-ObservationInterpretation code U (wrong display)
walk(
  if type == "object" and
     .system? == "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation" and
     .code? == "U" then
    del(.display)
  else . end
) |

# Fix 4: TPN with no system field
walk(
  if type == "object" and .code? == "TPN" and (.system == null or .system == "") then
    .system = "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation" |
    .code = "U" |
    del(.display)
  else . end
) |

# Fix 5: Remove pulse-oximetry profile so L/min is not validated against Vital Signs Units VS
.entry |= map(
  if .resource.resourceType == "Observation" and
     (.resource.meta.profile != null) and
     (.resource.meta.profile | type) == "array" and
     (.resource.meta.profile | map(select(contains("pulse-oximetry"))) | length) > 0 then
    .resource.meta.profile |= map(select(contains("pulse-oximetry") | not))
  else . end
) |

# Fix 6: Remove referenceRange from LysoPC observations (value < 1 constraint)
.entry |= map(
  if .resource.resourceType == "Observation" and
     (.resource.id != null) and
     (.resource.id | IN(
       "c819c019-d092-a836-47a1-befd8d7f65b4",
       "69977854-c548-5036-6236-85bfd38f6ed0",
       "601bd8f3-bb90-a8df-f3ef-9771bdc3bab9"
     )) then
    .resource |= del(.referenceRange)
  else . end
) |

# Fix 7: obs-6 - remove dataAbsentReason when value is present
.entry |= map(
  if .resource.resourceType == "Observation" and
     .resource.dataAbsentReason != null and (
       .resource.valueQuantity != null or
       .resource.valueCodeableConcept != null or
       .resource.valueString != null
     ) then
    .resource |= del(.dataAbsentReason)
  else . end
) |

# Fix 8: null time fields
walk(
  if type == "object" and has("time") and .time == null then del(.time)
  else . end
) |

# Fix 9: ext-1 - extension has both child extensions and value
.entry |= map(
  if .resource.resourceType == "Patient" or .resource.resourceType == "Observation" then
    if (.resource.extension | type) == "array" then
      .resource.extension |= map(
        if (.extension | type) == "array" and (.extension | length) > 0 and
           (has("valueCode") or has("valueString") or has("valueBoolean") or
            has("valueInteger") or has("valueQuantity") or has("valueCodeableConcept")) then
          del(.extension)
        else . end)
    else . end
  else . end

)
