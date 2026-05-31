# =============================================================================
# fix_r4_bundle_final.jq — Final 6 fixes for HAPI FHIR R4 transaction bundle
# =============================================================================
# Fixes:
#   1. Reverse ContactPoint.system corruption (urn:local:phone → phone etc.)
#   2. Remove urn:local:None (was null/missing system in source data)
#   3. Delete explicit null unit values on Observation quantities
#   4. Add MedicationRequest.requester where missing
#   5. Add Coverage.beneficiary where missing
#   6. Add RelatedPerson.patient where missing
#   7. Add Composition.author where missing
#
# Usage:
#   jq -f fix_r4_bundle_final.jq clean_bundle_r4.json > clean_bundle_r4_final.json
#
# Or inline:
#   jq -f fix_r4_bundle_final.jq input.json > output.json
# =============================================================================

# ── Fix 1 & 2: Reverse ContactPoint.system corruption ────────────────────────
# The prior Identifier.system fix over-fired and prefixed FHIR ContactPoint
# enum values (phone, email, fax etc.) with "urn:local:".
# These are not URI systems — they are fixed FHIR code values and must be
# restored to their original form.
# urn:local:None was a null/missing system stringified by Python — remove it.
# urn:local:MR is a legitimate local identifier system — leave it unchanged.
walk(
  if type == "object" and .system? != null then
    if   .system == "urn:local:phone" then .system = "phone"
    elif .system == "urn:local:email" then .system = "email"
    elif .system == "urn:local:fax"   then .system = "fax"
    elif .system == "urn:local:url"   then .system = "url"
    elif .system == "urn:local:sms"   then .system = "sms"
    elif .system == "urn:local:pager" then .system = "pager"
    elif .system == "urn:local:other" then .system = "other"
    elif .system == "urn:local:None"  then del(.system)
    else . end
  else . end
) |

# ── Fix 3: Remove explicit null unit values ───────────────────────────────────
# HAPI requires unit to be absent or a non-null string.
# Affects Observation.valueQuantity, component[].valueQuantity etc.
walk(
  if type == "object" and has("unit") and .unit == null then
    del(.unit)
  else . end
) |

# ── Fix 4: Add MedicationRequest.requester ────────────────────────────────────
# Required when intent = "order". All MedicationRequests in this bundle
# have intent = "order" (set by prior fix) so all need requester.
.entry |= map(
  if .resource.resourceType == "MedicationRequest" and
     .resource.requester == null then
    .resource.requester = {"display": "Unknown"}
  else . end
) |

# ── Fix 5: Add Coverage.beneficiary ──────────────────────────────────────────
# Required field (1..1) in R4.
.entry |= map(
  if .resource.resourceType == "Coverage" and
     .resource.beneficiary == null then
    .resource.beneficiary = {"display": "Unknown"}
  else . end
) |

# ── Fix 6: Add RelatedPerson.patient ─────────────────────────────────────────
# Required field (1..1) in R4.
.entry |= map(
  if .resource.resourceType == "RelatedPerson" and
     .resource.patient == null then
    .resource.patient = {"display": "Unknown"}
  else . end
) |

# ── Fix 7: Add Composition.author ────────────────────────────────────────────
# Required field (1..*) in R4.
.entry |= map(
  if .resource.resourceType == "Composition" and
     (.resource.author == null or (.resource.author | length) == 0) then
    .resource.author = [{"display": "Unknown"}]
  else . end
)
