# =============================================================================
# fix_helios_external_codesystems.jq
# Apply SECOND after fix_helios_bundle_all.jq (or after fix_helios_bundle.py)
# Fixes external CodeSystem issues that HAPI 8.8.0 cannot validate
#
# Usage:
#   jq -f fix_helios_external_codesystems.jq test-data-step1.json > test-data-fixed.json
#   jq '.entry | length' test-data-fixed.json   # should be 813
# =============================================================================

# Step 1: Fix Coverage.relationship BEFORE external system replacement
# (policyholder-relationship is not known to HAPI - map to subscriber-relationship)
.entry |= map(
  if .resource.resourceType == "Coverage" then
    (if (.resource.relationship.coding | type) == "array" then
      .resource.relationship.coding |= map(
        if (.system | startswith("http://hl7.org/fhir/policyholder-relationship")) then
          {"system": "http://terminology.hl7.org/CodeSystem/subscriber-relationship",
           "code": .code, "display": .display}
        else . end)
    else . end)
  else . end
) |

# Step 2: Replace codings from truly external/unknown CodeSystems with data-absent-reason
# NOTE: Do NOT include required-binding systems here - they are restored in Steps 3-5
walk(
  if type == "object" and
     (.system | type) == "string" and
     (.code | type) == "string" and
     (
       (.system | startswith("https://www.nubc.org")) or
       (.system | startswith("https://www.cms.gov")) or
       (.system | startswith("https://fhir.cerner.com")) or
       (.system | startswith("http://smarthealthit.org")) or
       (.system | startswith("https://cap.org")) or
       (.system | startswith("http://cap.org")) or
       (.system | startswith("http://id.who.int")) or
       (.system | startswith("https://example.org")) or
       (.system | startswith("https://clinicaltables.nlm.nih.gov")) or
       (.system | test("^https?://hl7.org/fhir/R4/codesystem")) or
       (.system | test("^https?://build.fhir.org/ig")) or
       (.system | startswith("http://hl7.org/fhir/us/sdoh-clinicalcare/CodeSystem/")) or
       (.system | startswith("http://hl7.org/fhir/us/cancer-reporting/CodeSystem/")) or
       (.system | IN(
         "http://terminology.hl7.org/CodeSystem/umls",
         "http://terminology.hl7.org/CodeSystem/adjudication",
         "http://terminology.hl7.org/CodeSystem/occupation-cdc-census",
         "http://terminology.hl7.org/CodeSystem/v2-0074",
         "http://terminology.hl7.org/CodeSystem/v2-0078",
         "http://terminology.hl7.org/CodeSystem/v2-0443",
         "http://terminology.hl7.org/CodeSystem/v3-ParticipationType",
         "http://terminology.hl7.org/CodeSystem/v3-NullFlavor"
       ))
     ) then
    {"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason",
     "code": "unknown", "display": "Unknown"}
  else . end
) |

# Step 3: Restore required-binding status fields on AllergyIntolerance
.entry |= map(
  if .resource.resourceType == "AllergyIntolerance" then
    (if (.resource.clinicalStatus.coding | type) == "array" then
      .resource.clinicalStatus.coding |= map(
        if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
          {"system": "http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical",
           "code": "active", "display": "Active"}
        else . end)
    else . end) |
    (if (.resource.verificationStatus.coding | type) == "array" then
      .resource.verificationStatus.coding |= map(
        if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
          {"system": "http://terminology.hl7.org/CodeSystem/allergyintolerance-verification",
           "code": "unconfirmed", "display": "Unconfirmed"}
        else . end)
    else . end)
  else . end
) |

# Step 4: Restore required-binding status fields on Condition
.entry |= map(
  if .resource.resourceType == "Condition" then
    (if (.resource.clinicalStatus.coding | type) == "array" then
      .resource.clinicalStatus.coding |= map(
        if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
          {"system": "http://terminology.hl7.org/CodeSystem/condition-clinical",
           "code": "active", "display": "Active"}
        else . end)
    else . end) |
    (if (.resource.verificationStatus.coding | type) == "array" then
      .resource.verificationStatus.coding |= map(
        if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
          {"system": "http://terminology.hl7.org/CodeSystem/condition-ver-status",
           "code": "confirmed", "display": "Confirmed"}
        else . end)
    else . end)
  else . end
) |

# Step 5: Restore other required-binding fields
# Claim/EOB/ClaimResponse.type -> claim-type
.entry |= map(
  if (.resource.resourceType == "Claim" or
      .resource.resourceType == "ClaimResponse" or
      .resource.resourceType == "ExplanationOfBenefit") and
     (.resource.type.coding | type) == "array" then
    .resource.type.coding |= map(
      if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
        {"system": "http://terminology.hl7.org/CodeSystem/claim-type",
         "code": "professional", "display": "Professional"}
      else . end)
  else . end
) |

# Encounter.hospitalization.dischargeDisposition
.entry |= map(
  if .resource.resourceType == "Encounter" and
     (.resource.hospitalization.dischargeDisposition.coding | type) == "array" then
    .resource.hospitalization.dischargeDisposition.coding |= map(
      if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
        {"system": "http://terminology.hl7.org/CodeSystem/discharge-disposition",
         "code": "long", "display": "Long-term care"}
      else . end)
  else . end
) |

# Organization.type
.entry |= map(
  if .resource.resourceType == "Organization" and
     (.resource.type | type) == "array" then
    .resource.type |= map(
      .coding |= map(
        if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
          {"system": "http://terminology.hl7.org/CodeSystem/organization-type",
           "code": "prov", "display": "Healthcare Provider"}
        else . end))
  else . end
) |

# Claim/ClaimResponse.payee.type
.entry |= map(
  if .resource.resourceType == "Claim" or .resource.resourceType == "ClaimResponse" then
    if (.resource.payee.type.coding | type) == "array" then
      .resource.payee.type.coding |= map(
        if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
          {"system": "http://terminology.hl7.org/CodeSystem/payeetype",
           "code": "provider", "display": "Provider"}
        else . end)
    else . end
  else . end
) |

# Patient.maritalStatus
.entry |= map(
  if .resource.resourceType == "Patient" and
     (.resource.maritalStatus.coding | type) == "array" then
    .resource.maritalStatus.coding |= map(
      if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
        {"system": "http://terminology.hl7.org/CodeSystem/v3-MaritalStatus",
         "code": "S", "display": "Never Married"}
      else . end)
  else . end
) |

# DiagnosticReport.category
.entry |= map(
  if .resource.resourceType == "DiagnosticReport" and
     (.resource.category | type) == "array" then
    .resource.category |= map(
      .coding |= map(
        if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
          {"system": "http://terminology.hl7.org/CodeSystem/v2-0074",
           "code": "LAB", "display": "Laboratory"}
        else . end))
  else . end
) |

# Observation.interpretation
.entry |= map(
  if .resource.resourceType == "Observation" and
     (.resource.interpretation | type) == "array" then
    .resource.interpretation |= map(
      .coding |= map(
        if .system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" then
          {"system": "http://terminology.hl7.org/CodeSystem/v2-0078",
           "code": "A", "display": "Abnormal"}
        else . end))
  else . end
) |

# Step 6: Remove empty onAdmission objects from Claim.diagnosis
.entry |= map(
  if .resource.resourceType == "Claim" and
     (.resource.diagnosis | type) == "array" then
    .resource.diagnosis |= map(
      if .onAdmission != null and (.onAdmission | keys | length) == 0 then
        del(.onAdmission)
      else . end)
  else . end
) |

# Step 7: Remove empty _birthDate.extension arrays from Patient
.entry |= map(
  if .resource.resourceType == "Patient" and
     (.resource._birthDate | type) == "object" and
     (.resource._birthDate.extension | type) == "array" and
     (.resource._birthDate.extension | length) == 0 then
    .resource._birthDate |= del(.extension)
  else . end
) |

# Step 8: Replace empty objects {} with data-absent-reason
walk(
  if type == "object" and (. == {}) then
    {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason",
                 "code": "unknown", "display": "Unknown"}]}
  else . end
) |

# Step 9: Remove empty meta.profile arrays
.entry |= map(
  if (.resource.meta.profile | type) == "array" and
     (.resource.meta.profile | length) == 0 then
    .resource.meta |= del(.profile)
  else . end
) |

# Step 10: Remove all meta.profile declarations
# (prevents SNOMED ValueSet expansion failures during profile validation)
.entry |= map(.resource.meta |= del(.profile)) |

# Step 11: Remove unknown external extensions
.entry |= map(
  if .resource != null and (.resource.extension | type) == "array" then
    .resource.extension |= map(select(
      type != "object" or
      ((.url? | strings | startswith("http://mihin.org")) | not) and
      ((.url? | strings | startswith("http://fhir-registry.smarthealthit.org")) | not)
    ))
  else . end
) |

# Step 12: Fix US Core condition-category codes not in base FHIR ValueSet
.entry |= map(
  if .resource.resourceType == "Condition" and
     (.resource.category | type) == "array" then
    .resource.category |= map(
      if (.coding | type) == "array" then
        .coding |= map(
          if (.system | strings | contains("us/core/CodeSystem/condition-category")) or
             (.system == "http://terminology.hl7.org/CodeSystem/data-absent-reason" and .code == "unknown") then
            {"system": "http://terminology.hl7.org/CodeSystem/condition-category",
             "code": "problem-list-item", "display": "Problem List Item"}
          else . end)
      else . end)
  else . end
) |

# Step 13: Remove ExplanationOfBenefit.priority
# (processpriority CodeSystem vs ValueSet HAPI bug - priority not required on EOB)
.entry |= map(
  if .resource.resourceType == "ExplanationOfBenefit" then
    .resource |= del(.priority)
  else . end
) |

# Step 14: Remove processpriority display (causes CS vs VS error)
walk(
  if type == "object" and
     .system? == "http://terminology.hl7.org/CodeSystem/processpriority" then
    del(.display)
  else . end
) |

# Step 15: Fix coding objects missing a system field
walk(
  if type == "object" and has("code") and (has("system") | not) and
     (.code | type) == "string" then
    if .code == "complete" then
      . + {"system": "http://terminology.hl7.org/CodeSystem/ex-paymenttype"}
    elif .code == "2106-3" or .code == "2135-2" then
      . + {"system": "urn:oid:2.16.840.1.113883.6.238"}
    else . end
  else . end
) |

# Step 16: Remove v2-0131 display (HAPI is strict about canonical display)
walk(
  if type == "object" and
     .system? == "http://terminology.hl7.org/CodeSystem/v2-0131" and
     .code? == "N" then
    del(.display)
  else . end
) |

# Step 17: Fix QuestionnaireResponse nested ul HTML
.entry |= map(
  if .resource.resourceType == "QuestionnaireResponse" and
     (.resource.text.div | strings | contains("<ul><li><ul>")) then
    .resource.text.div = "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>Narrative not available</p></div>"
  else . end
) |

# Step 18: Final null/empty cleanup (MUST BE LAST)
walk(
  if type == "object" then
    (if has("issued") and .issued == null then del(.issued) else . end) |
    (if has("extension") and .extension == null then del(.extension) else . end)
  else . end
)
