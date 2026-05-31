#!/usr/bin/env bash
# =============================================================================
# fix_r4_bundle_22.sh — Fix HAPI FHIR R4 transaction bundle errors identified
#                       in load_fhir_bundle_tee_22.out (HTTP 422, 4113 errors)
# =============================================================================
# Fixes applied:
#   - Missing fullUrl / relative fullUrl on bundle entries
#   - Observation.status missing (→ "final")
#   - Observation.effective[x] missing (→ "1970-01-01T00:00:00Z")
#   - Incorrect head-circumference-percentile profile on raw measurement obs
#   - Encounter.status missing (→ "finished")
#   - Encounter.class missing (→ AMB)
#   - Encounter.location.location missing
#   - Specimen.type missing
#   - Composition required fields missing (status, date, title)
#   - Condition.clinicalStatus/verificationStatus wrong case (Active→active)
#   - Condition CodeSystem URLs (ValueSet→CodeSystem)
#   - Condition con-4: abatement present but code not "resolved"
#   - MedicationRequest.subject missing
#   - Condition.subject missing
#   - us-core-birthsex invalid codes ("Female"→"F", trim whitespace)
#   - UCUM unit encoding errors (mmHg, mIU/L, uM, Âµg/dL)
#   - mihin copyright extensions stripped
#   - Identifier.system local references prefixed with urn:local:
#
# Usage:
#   ./fix_r4_bundle_22.sh <input_bundle.json> [output_bundle.json]
#
# Example:
#   ./fix_r4_bundle_22.sh raw_bundle.json clean_bundle_r4.json
# =============================================================================

set -euo pipefail

INPUT="${1:-}"
OUTPUT="${2:-clean_bundle_r4.json}"
FHIR_BASE_URL="${FHIR_BASE_URL:-http://localhost:8080/fhir}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

[[ -z "$INPUT" ]]  && die "No input file.\nUsage: $0 <input_bundle.json> [output_bundle.json]"
[[ -f "$INPUT" ]]  || die "File not found: $INPUT"
command -v jq &>/dev/null || die "jq is not installed."

BEFORE=$(jq '.entry | length' "$INPUT")
info "Input        : $INPUT"
info "Output       : $OUTPUT"
info "FHIR base URL: $FHIR_BASE_URL"
info "Entry count  : $BEFORE"
echo

jq --arg base "$FHIR_BASE_URL" '

.entry |= map(

  # ── ExplanationOfBenefit ────────────────────────────────────────────────
  if .resource.resourceType == "ExplanationOfBenefit" then
    .resource |= (. + {
      use:      (.use      // "claim"),
      outcome:  (.outcome  // "complete"),
      created:  (.created  // "1970-01-01T00:00:00Z"),
      provider: (.provider // {"display": "Unknown"}),
      insurer:  (.insurer  // {"display": "Unknown"})
    }) |
    if (.resource.insurance | type) == "array" then
      .resource.insurance |= map(. + {focal: (.focal // true)})
    else . end |
    if (.resource.total | type) == "array" then
      .resource.total |= map(
        if .amount == null then
          . + {amount: {"value": 0, "currency": "USD"}}
        else . end)
    else . end

  # ── Claim ──────────────────────────────────────────────────────────────
  elif .resource.resourceType == "Claim" then
    .resource |= (. + {
      priority: (.priority // {"coding": [{"code": "normal"}]}),
      created:  (.created  // "1970-01-01T00:00:00Z"),
      provider: (.provider // {"display": "Unknown"})
    }) |
    if (.resource.item | type) == "array" then
      .resource.item |= map(. + {
        productOrService: (.productOrService // {
          "coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/data-absent-reason",
            "code":   "unknown"
          }]
        })
      })
    else . end

  # ── Coverage ───────────────────────────────────────────────────────────
  elif .resource.resourceType == "Coverage" then
    .resource |= (. + {
      status: (.status // "active"),
      payor:  (.payor  // [{"display": "Unknown"}])
    })

  # ── MedicationRequest ──────────────────────────────────────────────────
  elif .resource.resourceType == "MedicationRequest" then
    .resource |= (. + {
      status: (.status // "active"),
      intent: (.intent // "order")
    }) |
    if .resource.medicationCodeableConcept == null and
       .resource.medicationReference == null then
      .resource.medicationCodeableConcept = {
        "coding": [{
          "system": "http://terminology.hl7.org/CodeSystem/data-absent-reason",
          "code":   "unknown"
        }]
      }
    else . end |
    if .resource.subject == null then
      .resource.subject = {"display": "Unknown"}
    else . end

  # ── Procedure ──────────────────────────────────────────────────────────
  elif .resource.resourceType == "Procedure" then
    .resource |= (. + {status: (.status // "unknown")})

  # ── Observation ────────────────────────────────────────────────────────
  elif .resource.resourceType == "Observation" then
    .resource |= (. + {status: (.status // "final")}) |
    # Add missing effective[x]
    if .resource.effectiveDateTime == null and
       .resource.effectivePeriod   == null and
       .resource.effectiveTiming   == null and
       .resource.effectiveInstant  == null then
      .resource.effectiveDateTime = "1970-01-01T00:00:00Z"
    else . end |
    # Remove incorrect head-circumference-percentile profile from raw
    # measurement Observations (code 8287-5 is cm, not percentile 8289-1)
    if (.resource.meta.profile | type) == "array" then
      .resource.meta.profile |= map(select(
        startswith("http://hl7.org/fhir/us/core/StructureDefinition/head-occipital-frontal-circumference-percentile") | not
      ))
    else . end

  # ── Encounter ──────────────────────────────────────────────────────────
  elif .resource.resourceType == "Encounter" then
    .resource |= (. + {
      status: (.status // "finished"),
      class:  (.class  // {
        "system":  "http://terminology.hl7.org/CodeSystem/v3-ActCode",
        "code":    "AMB",
        "display": "ambulatory"
      })
    }) |
    if .resource.subject == null then
      .resource.subject = {"display": "Unknown"}
    else . end |
    if (.resource.location | type) == "array" then
      .resource.location |= map(
        if .location == null then
          . + {location: {"display": "Unknown"}}
        else . end)
    else . end

  # ── Specimen ───────────────────────────────────────────────────────────
  elif .resource.resourceType == "Specimen" then
    .resource |= (. + {
      type: (.type // {
        "coding": [{
          "system": "http://terminology.hl7.org/CodeSystem/data-absent-reason",
          "code":   "unknown"
        }]
      })
    })

  # ── Condition ──────────────────────────────────────────────────────────
  # Uses direct path assignments to avoid jq |= pipe scoping issue
  elif .resource.resourceType == "Condition" then
    (if (.resource.clinicalStatus.coding | type) == "array" then
       .resource.clinicalStatus.coding |= map(
         .system = "http://terminology.hl7.org/CodeSystem/condition-clinical" |
         .code   |= ascii_downcase)
     else . end) |
    (if (.resource.verificationStatus.coding | type) == "array" then
       .resource.verificationStatus.coding |= map(
         .system = "http://terminology.hl7.org/CodeSystem/condition-ver-status" |
         .code   |= ascii_downcase)
     else . end) |
    (if (.resource.category | type) == "array" then
       .resource.category |= map(
         if (.coding | type) == "array" then
           .coding |= map(
             if .system == "http://hl7.org/fhir/ValueSet/condition-category" then
               .system = "http://terminology.hl7.org/CodeSystem/condition-category"
             else . end)
         else . end)
     else . end) |
    (if .resource.subject == null then
       .resource.subject = {"display": "Unknown"}
     else . end) |
    (if .resource.abatement != null then
       .resource.clinicalStatus.coding[0].code = "resolved"
     else . end)

  # ── Composition ────────────────────────────────────────────────────────
  elif .resource.resourceType == "Composition" then
    .resource |= (. + {
      status: (.status // "final"),
      date:   (.date   // "1970-01-01T00:00:00Z"),
      title:  (.title  // "Unknown")
    })

  else . end

) |

# ── Add / fix fullUrl on every entry ──────────────────────────────────────
.entry |= map(
  if has("fullUrl") | not then
    . + {fullUrl: ($base + "/" + .resource.resourceType + "/" + .resource.id)}
  elif (.fullUrl | (startswith("http") or startswith("urn:")) | not) then
    .fullUrl = ($base + "/" + .fullUrl)
  else . end
) |

# ── Normalize us-core-birthsex codes ──────────────────────────────────────
walk(
  if type == "object" and
     .url? == "http://hl7.org/fhir/us/core/StructureDefinition/us-core-birthsex" then
    .valueCode |= (
      ltrimstr(" ") | rtrimstr(" ") |
      if   . == "Female" then "F"
      elif . == "Male"   then "M"
      else . end)
  else . end
) |

# ── Fix UCUM unit encoding errors ─────────────────────────────────────────
walk(
  if type == "object" and .system? == "http://unitsofmeasure.org" then
    .code |= (
      if   . == "mmHg"     then "mm[Hg]"
      elif . == "mIU/L"    then "m[IU]/L"
      elif . == "uM"       then "umol/L"
      elif . == "Âµg/dL"  then "ug/dL"
      else . end) |
    .unit |= (
      if . == null         then .
      elif . == "mmHg"     then "mm[Hg]"
      elif . == "mIU/L"    then "m[IU]/L"
      elif . == "uM"       then "umol/L"
      elif . == "Âµg/dL"  then "ug/dL"
      else . end)
  else . end
) |

# ── Strip mihin copyright extensions ──────────────────────────────────────
walk(
  if type == "array" then
    map(select(
      type != "object" or
      (.url? != "http://mihin.org/extension/copyright")
    ))
  else . end
) |

# ── Fix Identifier.system local references ────────────────────────────────
walk(
  if type == "object" and has("system") and has("value") and
     .system != null and
     (.system | (startswith("http") or startswith("urn:") or startswith("oid:")) | not) then
    .system = ("urn:local:" + .system)
  else . end
)

' "$INPUT" > "$OUTPUT"

AFTER=$(jq '.entry | length' "$OUTPUT")

echo
success "Conversion complete."
info "Entries before : $BEFORE"
info "Entries after  : $AFTER"
[[ "$BEFORE" != "$AFTER" ]] && warn "Entry count changed — review output before posting."
info "Output written : $OUTPUT"
echo
info "Next step: post with load_fhir_bundle.sh"
info "  DEX_TOKEN=\$TOKEN ./load_fhir_bundle.sh $OUTPUT"

