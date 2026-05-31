#!/usr/bin/env bash
# =============================================================================
# convert_stu3_to_r4.sh — Fix STU3-era FHIR bundle for HAPI FHIR R4 ingestion
# =============================================================================
# Usage:
#   ./convert_stu3_to_r4.sh <input_bundle.json> [output_bundle.json]
#
# Examples:
#   ./convert_stu3_to_r4.sh bundle.json
#   ./convert_stu3_to_r4.sh bundle.json clean_bundle_r4.json
# =============================================================================

set -euo pipefail

INPUT="${1:-}"
OUTPUT="${2:-clean_bundle_r4.json}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

[[ -z "$INPUT" ]] && die "No input file specified.\nUsage: $0 <input_bundle.json> [output_bundle.json]"
[[ -f "$INPUT" ]] || die "File not found: $INPUT"
command -v jq &>/dev/null || die "jq is not installed."

info "Input  : $INPUT"
info "Output : $OUTPUT"

BEFORE=$(jq '.entry | length' "$INPUT")
info "Entry count : $BEFORE"
echo

jq '
.entry |= map(

  # ── ExplanationOfBenefit ──────────────────────────────────────────────────
  # Uses // (alternative) operator for all scalar/object defaults so that
  # ALL fields are set in a single object merge — avoids the jq |= pipe
  # scoping issue where only the first chained update survives.
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

  # ── Claim ─────────────────────────────────────────────────────────────────
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

  # ── Coverage ──────────────────────────────────────────────────────────────
  elif .resource.resourceType == "Coverage" then
    .resource |= (. + {
      status: (.status // "active"),
      payor:  (.payor  // [{"display": "Unknown"}])
    })

  # ── MedicationRequest ─────────────────────────────────────────────────────
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
    else . end

  # ── Procedure ─────────────────────────────────────────────────────────────
  elif .resource.resourceType == "Procedure" then
    .resource |= (. + {status: (.status // "unknown")})

  # ── Condition ─────────────────────────────────────────────────────────────
  # Uses direct .resource.field path assignments at the entry level rather
  # than nested |= chains inside .resource |= — this is required because
  # chained pipes inside |= drop all but the last update in jq.
  elif .resource.resourceType == "Condition" then
    (if (.resource.clinicalStatus.coding | type) == "array" then
       .resource.clinicalStatus.coding |= map(
         .system = "http://terminology.hl7.org/CodeSystem/condition-clinical")
     else . end) |
    (if (.resource.verificationStatus.coding | type) == "array" then
       .resource.verificationStatus.coding |= map(
         .system = "http://terminology.hl7.org/CodeSystem/condition-ver-status")
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
    (if .resource.abatement != null then
       .resource.clinicalStatus.coding[0].code = "resolved"
     else . end)

  else . end

) |

# ── Strip mihin copyright extensions from entire bundle ───────────────────
walk(
  if type == "array" then
    map(select(
      type != "object" or
      (.url? != "http://mihin.org/extension/copyright")
    ))
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
