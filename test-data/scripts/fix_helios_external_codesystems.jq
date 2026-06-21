# =============================================================================
# fix_helios_external_codesystems.jq
# Fixes external CodeSystem URLs that HAPI cannot validate.
# Apply this to test-data-helios-final7.json
#
# Usage:
#   jq -f fix_helios_external_codesystems.jq test-data-helios-final7.json \
#      > test-data-helios-final11.json
# =============================================================================

# Step 1: Fix Coverage.relationship FIRST (before external system replacement)
# http://hl7.org/fhir/policyholder-relationship is not known to HAPI -
# must map to http://terminology.hl7.org/CodeSystem/subscriber-relationship
.entry |= map(
  if .resource.resourceType == "Coverage" then
    (if (.resource.relationship.coding | type) == "array" then
      .resource.relationship.coding |= map(
        if (.system | startswith("http://hl7.org/fhir/policyholder-relationship")) then
          {
            "system": "http://terminology.hl7.org/CodeSystem/subscriber-relationship",
            "code": .code,
            "display": .display
          }
        else . end)
    else . end)
  else . end
) |

# Step 2: Replace codings from truly external/unknown CodeSystems with data-absent-reason
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
       (.system | test("^https?://build.fhir.org/ig"))
     ) then
    {
      "system": "http://terminology.hl7.org/CodeSystem/data-absent-reason",
      "code": "unknown",
      "display": "Unknown"
    }
  else . end
) |

# Step 3: Remove empty onAdmission objects from Claim.diagnosis
.entry |= map(
  if .resource.resourceType == "Claim" and
     (.resource.diagnosis | type) == "array" then
    .resource.diagnosis |= map(
      if .onAdmission != null and (.onAdmission | keys | length) == 0 then
        del(.onAdmission)
      else . end)
  else . end
) |

# Step 4: Remove empty _birthDate.extension arrays from Patient
.entry |= map(
  if .resource.resourceType == "Patient" and
     (.resource._birthDate | type) == "object" and
     (.resource._birthDate.extension | type) == "array" and
     (.resource._birthDate.extension | length) == 0 then
    .resource._birthDate |= del(.extension)
  else . end
) |

# Step 5: Replace any remaining empty objects {} with data-absent-reason
walk(
  if type == "object" and (. == {}) then
    {
      "coding": [{
        "system": "http://terminology.hl7.org/CodeSystem/data-absent-reason",
        "code": "unknown",
        "display": "Unknown"
      }]
    }
  else . end
) |

# Step 6: Final null cleanup
walk(
  if type == "object" then
    (if has("issued") and .issued == null then del(.issued) else . end) |
    (if has("extension") and .extension == null then del(.extension) else . end)
  else . end
)
