#!/usr/bin/env bash
# =============================================================================
# load_fhir_bundle.sh — Upload a FHIR Bundle (JSON) to the CDC PHDI / DIBBs
#                       DEX Connectathon Sandbox (Azure Health Data Services)
# =============================================================================
# Usage:
#   ./load_fhir_bundle.sh <bundle.json> [FHIR_BASE_URL]
#
# Required environment variables:
#   DEX_TOKEN          Bearer token issued by SAMS / DEX OAuth2 (required)
#
# Optional environment variables (override defaults below):
#   FHIR_BASE_URL      Full DEX FHIR sandbox base URL
#   DEX_DESTINATION_ID Destination program identifier   (x-meta-destination-id)
#   DEX_EXT_SOURCE     Originating source system label  (x-meta-ext-source)
#   DEX_EXT_EVENT      Event / use-case label           (x-meta-ext-event)
#   DEX_EXT_ENTITY     Submitting jurisdiction / entity (x-meta-ext-entity)
#
# Examples:
#   DEX_TOKEN="eyJ..." ./load_fhir_bundle.sh patient_bundle.json
#   DEX_TOKEN="eyJ..." FHIR_BASE_URL="https://sandbox.fhir.cdc.gov/fhir" \
#     ./load_fhir_bundle.sh patient_bundle.json
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Configuration — fill in defaults that match your connectathon brief
# --------------------------------------------------------------------------- #
BUNDLE_FILE="${1:-}"
#FHIR_BASE_URL="${FHIR_BASE_URL:-https://sandbox.fhir.cdc.gov/fhir}"
FHIR_BASE_URL="${FHIR_BASE_URL:-http://localhost:8080/fhir}"


# DEX / DIBBs metadata headers — values provided by CDC connectathon organisers
DEX_TOKEN="${DEX_TOKEN:-notokenrequired}"
DEX_DESTINATION_ID="${DEX_DESTINATION_ID:-dex-testing}"
DEX_EXT_SOURCE="${DEX_EXT_SOURCE:-}"       # e.g. "my-jurisdiction-ehr"
DEX_EXT_EVENT="${DEX_EXT_EVENT:-}"         # e.g. "case-report"
DEX_EXT_ENTITY="${DEX_EXT_ENTITY:-}"       # e.g. "CDC-PHDI-Connectathon"

TIMEOUT=120          # DEX sandbox can be slow; allow 2 minutes
VERBOSE=false        # set to true for full curl output

# --------------------------------------------------------------------------- #
# Colour helpers
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# --------------------------------------------------------------------------- #
# Pre-flight checks
# --------------------------------------------------------------------------- #
[[ -z "$BUNDLE_FILE" ]] && \
  die "No bundle file specified.\nUsage: DEX_TOKEN=<token> $0 <bundle.json> [FHIR_BASE_URL]"
[[ -f "$BUNDLE_FILE" ]] || die "File not found: $BUNDLE_FILE"

[[ -z "$DEX_TOKEN" ]] && \
  die "DEX_TOKEN is not set. Export your SAMS/DEX Bearer token:\n  export DEX_TOKEN='eyJ...'"

command -v curl &>/dev/null || die "curl is not installed."
command -v jq   &>/dev/null || warn "jq not found — response will not be pretty-printed."

# --------------------------------------------------------------------------- #
# Validate that the file looks like a FHIR Bundle
# --------------------------------------------------------------------------- #
if command -v jq &>/dev/null; then
  RESOURCE_TYPE=$(jq -r '.resourceType // empty' "$BUNDLE_FILE" 2>/dev/null)
  BUNDLE_TYPE=$(jq -r '.type // empty'           "$BUNDLE_FILE" 2>/dev/null)
  BUNDLE_ID=$(jq -r '.id // empty'               "$BUNDLE_FILE" 2>/dev/null)

  [[ "$RESOURCE_TYPE" == "Bundle" ]] || \
    die "resourceType is '${RESOURCE_TYPE:-unknown}', expected 'Bundle'."

  info "Bundle id   : ${BUNDLE_ID:-<none>}"
  info "Bundle type : ${BUNDLE_TYPE:-<unset>}"
  ENTRY_COUNT=$(jq '.entry | length' "$BUNDLE_FILE" 2>/dev/null || echo "?")
  info "Entry count : $ENTRY_COUNT"

  # For PUT the URL must include the Bundle ID
  if [[ -n "$BUNDLE_ID" ]]; then
    ENDPOINT="${FHIR_BASE_URL%/}/Bundle/${BUNDLE_ID}"
  else
    warn "Bundle has no .id — falling back to base URL (PUT without resource ID may fail)."
    ENDPOINT="${FHIR_BASE_URL%/}"
  fi
else
  ENDPOINT="${FHIR_BASE_URL%/}"
fi

# --------------------------------------------------------------------------- #
# Build curl options
# --------------------------------------------------------------------------- #
echo
echo -e "${BOLD}Target           :${RESET} CDC PHDI / DIBBs DEX Connectathon Sandbox"
echo -e "${BOLD}Method           :${RESET} PUT"
echo -e "${BOLD}Endpoint         :${RESET} ${ENDPOINT}"
echo -e "${BOLD}File             :${RESET} ${BUNDLE_FILE}"
echo -e "${BOLD}Destination-Id   :${RESET} ${DEX_DESTINATION_ID}"
echo "-----------------------------------------------------------"

CURL_OPTS=(
  --silent
  --show-error
  --write-out "\n__HTTP_STATUS__%{http_code}"
  --request PUT
  --url "${ENDPOINT}"
  # Standard FHIR headers
  --header "Content-Type: application/fhir+json"
  --header "Accept: application/fhir+json"
  # DEX authentication
  # --header "Authorization: Bearer ${DEX_TOKEN}"
  # DEX metadata headers (required by DEX ingestion pipeline)
  # --header "x-meta-destination-id: ${DEX_DESTINATION_ID}"
  --max-time "${TIMEOUT}"
  --data-binary "@${BUNDLE_FILE}"
)

# Add optional DEX metadata headers only when set
[[ -n "$DEX_EXT_SOURCE" ]] && CURL_OPTS+=(--header "x-meta-ext-source: ${DEX_EXT_SOURCE}")
[[ -n "$DEX_EXT_EVENT"  ]] && CURL_OPTS+=(--header "x-meta-ext-event: ${DEX_EXT_EVENT}")
[[ -n "$DEX_EXT_ENTITY" ]] && CURL_OPTS+=(--header "x-meta-ext-entity: ${DEX_EXT_ENTITY}")

$VERBOSE && CURL_OPTS+=(--verbose)

# --------------------------------------------------------------------------- #
# Execute
# --------------------------------------------------------------------------- #
RAW_RESPONSE=$(curl "${CURL_OPTS[@]}" 2>&1) || {
  die "curl command failed. Is the DEX sandbox reachable at ${ENDPOINT}?"
}

# Split body and HTTP status code
HTTP_STATUS=$(echo "$RAW_RESPONSE" | grep -o '__HTTP_STATUS__[0-9]*' | cut -d'_' -f5)
BODY=$(echo "$RAW_RESPONSE" | sed 's/__HTTP_STATUS__[0-9]*$//')

# --------------------------------------------------------------------------- #
# Parse & display response
# --------------------------------------------------------------------------- #
echo
if command -v jq &>/dev/null; then
  echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
else
  echo "$BODY"
fi

echo
echo "-----------------------------------------------------------"
echo -e "${BOLD}HTTP Status: ${HTTP_STATUS}${RESET}"

# --------------------------------------------------------------------------- #
# Outcome summary
# --------------------------------------------------------------------------- #
case "$HTTP_STATUS" in
  200|201)
    success "Bundle submitted successfully to DEX sandbox (HTTP ${HTTP_STATUS})."
    if command -v jq &>/dev/null; then
      ISSUES=$(echo "$BODY" | jq -r '[.entry[]?.response.status] | map(select(. != null)) | .[]' 2>/dev/null || true)
      [[ -n "$ISSUES" ]] && { echo; info "Per-entry response status codes:"; echo "$ISSUES"; }
    fi
    ;;
  400)
    error "Bad request (HTTP 400). Check bundle structure or DEX metadata headers."
    exit 1 ;;
  401)
    error "Unauthorised (HTTP 401). DEX_TOKEN is missing, expired, or invalid."
    exit 1 ;;
  403)
    error "Forbidden (HTTP 403). Token lacks permission for destination '${DEX_DESTINATION_ID}'."
    exit 1 ;;
  404)
    error "Not found (HTTP 404). Check FHIR_BASE_URL and Bundle ID: ${ENDPOINT}"
    exit 1 ;;
  412)
    error "Precondition failed (HTTP 412). DEX may require If-Match / ETag for PUT."
    exit 1 ;;
  422)
    error "Unprocessable entity (HTTP 422). FHIR or DEX profile validation failed."
    exit 1 ;;
  429)
    error "Rate limited (HTTP 429). Wait and retry."
    exit 1 ;;
  *)
    warn "Unexpected HTTP status: ${HTTP_STATUS}."
    exit 1 ;;
esac

