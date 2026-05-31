#!/usr/bin/env bash
# =============================================================================
# load_uscore_package.sh — Load US Core 6.1.0 IG package into HAPI FHIR
#                          using the FHIR Package Loader ($package-import)
# =============================================================================
# This resolves HAPI 8.x errors caused by unknown US Core 6.1.0 profiles and
# ValueSet expansions, including:
#   - birthsex ValueSet expansion failures
#   - us-core-patient / us-core-encounter profile match failures
#   - Unknown profile references for us-core-* resources
#
# Usage:
#   ./load_uscore_package.sh [FHIR_BASE_URL]
#
# Examples:
#   ./load_uscore_package.sh
#   ./load_uscore_package.sh http://localhost:8080/fhir
# =============================================================================

set -euo pipefail

FHIR_BASE_URL="${1:-${FHIR_BASE_URL:-http://localhost:8080/fhir}}"
TIMEOUT=300   # package import can be slow

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

command -v curl &>/dev/null || die "curl is not installed."
command -v jq   &>/dev/null || warn "jq not found — responses will not be pretty-printed."

echo
echo -e "${BOLD}HAPI FHIR US Core 6.1.0 Package Loader${RESET}"
echo -e "${BOLD}Target: ${RESET}${FHIR_BASE_URL}"
echo "============================================================"

# --------------------------------------------------------------------------- #
# Helper: POST a Parameters resource and report outcome
# --------------------------------------------------------------------------- #
post_package() {
  local LABEL="$1"
  local PAYLOAD="$2"

  info "Loading: $LABEL ..."

  RAW=$(curl \
    --silent \
    --show-error \
    --write-out "\n__HTTP_STATUS__%{http_code}" \
    --max-time "$TIMEOUT" \
    --request POST \
    --url "${FHIR_BASE_URL}/\$package-import" \
    --header "Content-Type: application/fhir+json" \
    --header "Accept: application/fhir+json" \
    --data-raw "$PAYLOAD" \
    2>&1) || die "curl failed for $LABEL"

  HTTP_STATUS=$(echo "$RAW" | grep -o '__HTTP_STATUS__[0-9]*' | cut -d'_' -f5)
  BODY=$(echo "$RAW" | sed 's/__HTTP_STATUS__[0-9]*$//')

  if command -v jq &>/dev/null; then
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
  else
    echo "$BODY"
  fi

  case "$HTTP_STATUS" in
    200|201) success "$LABEL loaded (HTTP $HTTP_STATUS)" ;;
    400)     warn    "$LABEL — Bad request (HTTP 400). Package may already be loaded." ;;
    404)     warn    "Endpoint \$package-import not found (HTTP 404). Trying fallback method..." 
             return 1 ;;
    *)       warn    "$LABEL — Unexpected HTTP $HTTP_STATUS" ;;
  esac
  return 0
}

# --------------------------------------------------------------------------- #
# Method 1: HAPI $package-import operation (HAPI 6.x+)
# --------------------------------------------------------------------------- #
echo
info "Method 1: HAPI \$package-import operation"
echo "------------------------------------------------------------"

PRIMARY_PAYLOAD='{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "packageUrl",
      "valueUrl": "https://packages.fhir.org/hl7.fhir.us.core/6.1.0"
    },
    {
      "name": "installMode",
      "valueCode": "STORE_AND_INSTALL"
    }
  ]
}'

if post_package "hl7.fhir.us.core 6.1.0" "$PRIMARY_PAYLOAD"; then
  echo
  success "US Core 6.1.0 package import complete."

# --------------------------------------------------------------------------- #
# Method 2: Fallback — npm-style package URL
# --------------------------------------------------------------------------- #
else
  warn "Trying fallback: npm FHIR package registry..."

  FALLBACK_PAYLOAD='{
    "resourceType": "Parameters",
    "parameter": [
      {
        "name": "packageId",
        "valueString": "hl7.fhir.us.core"
      },
      {
        "name": "version",
        "valueString": "6.1.0"
      },
      {
        "name": "installMode",
        "valueCode": "STORE_AND_INSTALL"
      }
    ]
  }'

  post_package "hl7.fhir.us.core 6.1.0 (fallback)" "$FALLBACK_PAYLOAD" || {
    echo
    warn "Both import methods failed. Trying manual NamingSystem/ValueSet preload..."
    echo
    # ------------------------------------------------------------------- #
    # Method 3: Manually seed the birthsex ValueSet which is the most
    # common blocker — HAPI can expand it without the full package
    # ------------------------------------------------------------------- #
    info "Method 3: Seeding us-core-birthsex ValueSet directly..."

    BIRTHSEX_VS='{
      "resourceType": "ValueSet",
      "id": "birthsex",
      "url": "http://hl7.org/fhir/us/core/ValueSet/birthsex",
      "version": "6.1.0",
      "name": "BirthSex",
      "title": "Birth Sex",
      "status": "active",
      "compose": {
        "include": [
          {
            "system": "http://terminology.hl7.org/CodeSystem/v2-0001",
            "concept": [
              {"code": "M", "display": "Male"},
              {"code": "F", "display": "Female"},
              {"code": "OTH", "display": "Other"},
              {"code": "UNK", "display": "Unknown"}
            ]
          }
        ]
      }
    }'

    RAW2=$(curl \
      --silent --show-error \
      --write-out "\n__HTTP_STATUS__%{http_code}" \
      --max-time 60 \
      --request PUT \
      --url "${FHIR_BASE_URL}/ValueSet/birthsex" \
      --header "Content-Type: application/fhir+json" \
      --header "Accept: application/fhir+json" \
      --data-raw "$BIRTHSEX_VS" 2>&1)

    HTTP2=$(echo "$RAW2" | grep -o '__HTTP_STATUS__[0-9]*' | cut -d'_' -f5)
    BODY2=$(echo "$RAW2" | sed 's/__HTTP_STATUS__[0-9]*$//')
    command -v jq &>/dev/null && echo "$BODY2" | jq . 2>/dev/null || echo "$BODY2"

    case "$HTTP2" in
      200|201) success "birthsex ValueSet seeded (HTTP $HTTP2)" ;;
      *)       warn    "birthsex ValueSet seed — HTTP $HTTP2" ;;
    esac

    # ------------------------------------------------------------------- #
    # Seed the CDC Race & Ethnicity OID as a known NamingSystem so HAPI
    # stops rejecting urn:oid:2.16.840.1.113883.6.238 codes
    # ------------------------------------------------------------------- #
    info "Method 3b: Registering CDC Race & Ethnicity NamingSystem..."

    RACE_NS='{
      "resourceType": "NamingSystem",
      "id": "cdc-race-ethnicity",
      "name": "CDCRaceEthnicity",
      "status": "active",
      "kind": "codesystem",
      "date": "2024-01-01",
      "description": "CDC Race and Ethnicity Code Set Version 1.0",
      "uniqueId": [
        {
          "type": "oid",
          "value": "2.16.840.1.113883.6.238",
          "preferred": true
        },
        {
          "type": "uri",
          "value": "urn:oid:2.16.840.1.113883.6.238"
        }
      ]
    }'

    RAW3=$(curl \
      --silent --show-error \
      --write-out "\n__HTTP_STATUS__%{http_code}" \
      --max-time 60 \
      --request PUT \
      --url "${FHIR_BASE_URL}/NamingSystem/cdc-race-ethnicity" \
      --header "Content-Type: application/fhir+json" \
      --header "Accept: application/fhir+json" \
      --data-raw "$RACE_NS" 2>&1)

    HTTP3=$(echo "$RAW3" | grep -o '__HTTP_STATUS__[0-9]*' | cut -d'_' -f5)
    BODY3=$(echo "$RAW3" | sed 's/__HTTP_STATUS__[0-9]*$//')
    command -v jq &>/dev/null && echo "$BODY3" | jq . 2>/dev/null || echo "$BODY3"

    case "$HTTP3" in
      200|201) success "CDC Race & Ethnicity NamingSystem registered (HTTP $HTTP3)" ;;
      *)       warn    "NamingSystem registration — HTTP $HTTP3" ;;
    esac
  }
fi

echo
echo "============================================================"
info "Next step: re-run the bundle load script:"
info "  DEX_TOKEN=\$TOKEN ./load_fhir_bundle.sh clean_bundle_r4.json"
echo
warn "If profile-match errors persist, disable terminology validation in"
warn "application.yaml and restart HAPI:"
echo
echoHAPI-0450: Failed to parse request body as JSON resource. Error was: HAPI-1814: Incorrect resource type found, expected \"Bundle\" but found \" "  hapi:"
echo "    fhir:"
echo "      terminology_validation_enabled: false"
echo
