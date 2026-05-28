#!/usr/bin/env bash
# =============================================================================
# load_fhir_bundle.sh — Upload a FHIR Bundle (JSON) to a HAPI FHIR server
# =============================================================================
# Usage:
#   ./load_fhir_bundle.sh <bundle.json> [FHIR_BASE_URL]
#
# Examples:
#   ./load_fhir_bundle.sh patient_bundle.json
#   ./load_fhir_bundle.sh patient_bundle.json http://localhost:8080/fhir
#   FHIR_BASE_URL=https://my-hapi-server.com/fhir ./load_fhir_bundle.sh bundle.json
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
BUNDLE_FILE="${1:-}"
#FHIR_BASE_URL="${2:-${FHIR_BASE_URL:-http://localhost:8080/fhir}}"
FHIR_BASE_URL="${2:-${FHIR_BASE_URL:-http://localhost:4004//hapi-fhir-jpaserver/fhir}}"
TIMEOUT=60          # seconds per request
VERBOSE=false       # set to true for full curl output

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
[[ -z "$BUNDLE_FILE" ]] && die "No bundle file specified.\nUsage: $0 <bundle.json> [FHIR_BASE_URL]"
[[ -f "$BUNDLE_FILE" ]] || die "File not found: $BUNDLE_FILE"

command -v curl &>/dev/null || die "curl is not installed."
command -v jq  &>/dev/null || warn "jq not found — response will not be pretty-printed."

# --------------------------------------------------------------------------- #
# Validate that the file looks like a FHIR Bundle
# --------------------------------------------------------------------------- #
if command -v jq &>/dev/null; then
  RESOURCE_TYPE=$(jq -r '.resourceType // empty' "$BUNDLE_FILE" 2>/dev/null)
  BUNDLE_TYPE=$(jq -r '.type // empty'         "$BUNDLE_FILE" 2>/dev/null)

  [[ "$RESOURCE_TYPE" == "Bundle" ]] || \
    die "resourceType is '${RESOURCE_TYPE:-unknown}', expected 'Bundle'."

  info "Bundle type : ${BUNDLE_TYPE:-<unset>}"
  ENTRY_COUNT=$(jq '.entry | length' "$BUNDLE_FILE" 2>/dev/null || echo "?")
  info "Entry count : $ENTRY_COUNT"
fi

# --------------------------------------------------------------------------- #
# POST the bundle
# --------------------------------------------------------------------------- #
ENDPOINT="${FHIR_BASE_URL%/}"   # strip trailing slash

echo
echo -e "${BOLD}Uploading bundle to:${RESET} ${ENDPOINT}"
echo -e "${BOLD}File             :${RESET} ${BUNDLE_FILE}"
echo "-----------------------------------------------------------"

CURL_OPTS=(
  --silent
  --show-error
  --write-out "\n__HTTP_STATUS__%{http_code}"
  --request POST
  --url "${ENDPOINT}"
  --header "Content-Type: application/fhir+json"
  --header "Accept: application/fhir+json"
  --max-time "${TIMEOUT}"
  --data-binary "@${BUNDLE_FILE}"
)

$VERBOSE && CURL_OPTS+=(--verbose)

RAW_RESPONSE=$(curl "${CURL_OPTS[@]}" 2>&1) || {
  die "curl command failed. Is the server reachable at ${ENDPOINT}?"
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
    success "Bundle uploaded successfully (HTTP ${HTTP_STATUS})."
    if command -v jq &>/dev/null; then
      ISSUES=$(echo "$BODY" | jq -r '[.entry[]?.response.status] | map(select(. != null)) | .[]' 2>/dev/null || true)
      [[ -n "$ISSUES" ]] && { echo; info "Per-entry status codes:"; echo "$ISSUES"; }
    fi
    ;;
  400)
    error "Bad request (HTTP 400). The bundle may contain validation errors."
    exit 1 ;;
  401|403)
    error "Authentication / authorisation failure (HTTP ${HTTP_STATUS})."
    exit 1 ;;
  404)
    error "Endpoint not found (HTTP 404). Check FHIR_BASE_URL: ${ENDPOINT}"
    exit 1 ;;
  422)
    error "Unprocessable entity (HTTP 422). FHIR validation failed."
    exit 1 ;;
  *)
    warn "Unexpected HTTP status: ${HTTP_STATUS}."
    exit 1 ;;
esac
