

# Fix 1: PractitionerRole in Encounter.participant
.entry |= map(
  if .resource.resourceType == "Encounter" and
     (.resource.participant | type) == "array" then
    .resource.participant |= map(
      if (.individual?.reference? | type) == "string" and
         (.individual.reference | startswith("PractitionerRole/")) then
        .individual = {"display": "Unknown"}
      else . end)
  else . end
) |

# Fix 2: Delete display on all LOINC codings
walk(
  if type == "object" and .system? == "http://loinc.org" and .display? != null then
    del(.display)
  else . end
) |

# Fix 3: Delete display on all SNOMED codings
walk(
  if type == "object" and .system? == "http://snomed.info/sct" and .display? != null then
    del(.display)
  else . end
) |

# Fix 4: Remove unknown PLT/emergingIssues codes
walk(
  if type == "object" and .system? == "http://loinc.org" and
     (.code? | strings | test("^PLT[0-9]+$|^emergingIssues$")) then
    .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
    .code   = "unknown" |
    .display = "Unknown"
  else . end
) |

# Fix 5: Remove unknown SNOMED codes
walk(
  if type == "object" and .system? == "http://snomed.info/sct" and
     (.code? | strings |
      test("^(674814021000119000|880529761000119000|63706|62223|51725|72156|96002|44986800)$")) then
    .system  = "http://terminology.hl7.org/CodeSystem/data-absent-reason" |
    .code    = "unknown" |
    .display = "Unknown"
  else . end
) |

# Fix 6: v2-0203 code U wrong display
walk(
  if type == "object" and
     .system? == "http://terminology.hl7.org/CodeSystem/v2-0203" and
     .code? == "U" and .display? == "Unknown" then
    .display = "Unspecified identifier"
  else . end
) |

# Fix 7: v2-0203 Crowe
walk(
  if type == "object" and
     .system? == "http://terminology.hl7.org/CodeSystem/v2-0203" and
     .code? == "Crowe" then
    .code = "U" | .display = "Unspecified identifier"
  else . end
) |

# Fix 8: TBC/TPN in v3-ObservationInterpretation
walk(
  if type == "object" and
     .system? == "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation" and
     (.code? == "TBC" or .code? == "TPN") then
    .code = "U" | .display = "Unknown"
  else . end
) |

# Fix 9: L/min to {L}/min
walk(
  if type == "object" and .system? == "http://unitsofmeasure.org" and .code? == "L/min" then
    .code = "{L}/min"
  else . end
) |

# Fix 10: Z13.4 wrong display
walk(
  if type == "object" and
     .system? == "http://hl7.org/fhir/sid/icd-10-cm" and
     .code? == "Z13.4" then
    del(.display)
  else . end
) |

# Fix 11: obs-6
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

# Fix 12: null time fields
walk(
  if type == "object" and has("time") and .time == null then
    del(.time)
  else . end
) |

# Fix 13: ext-1
.entry |= map(
  if .resource.resourceType == "Patient" or
     .resource.resourceType == "Observation" then
    if (.resource.extension | type) == "array" then
      .resource.extension |= map(
        if (.extension | type) == "array" and (.extension | length) > 0 and
           (has("valueCode") or has("valueString") or has("valueBoolean") or
            has("valueInteger") or has("valueQuantity") or has("valueCodeableConcept")) then
          del(.extension)
        else . end)
    else . end
  else . end
) |

# Fix 14: valueInteger 0 to 1
.entry |= map(
  if .resource.resourceType == "Observation" then
    (if .resource.valueInteger? == 0 then .resource.valueInteger = 1 else . end) |
    (if (.resource.component | type) == "array" then
       .resource.component |= map(
         if .valueInteger? == 0 then .valueInteger = 1 else . end)
     else . end)
  else . end
)
