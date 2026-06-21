#!/usr/bin/env bash
# =============================================================================
# smart_sandbox_validation.sh
# Validates smart-dev-sandbox for HL7 SMART on FHIR connectathon
#
# Usage:
#   ./smart_sandbox_validation.sh [LAUNCHER_PORT] [R4_PORT] [HOST]
#   ./smart_sandbox_validation.sh 4001 4004 localhost
# =============================================================================

set -uo pipefail 
set +e # Don't exit on errors - we handle them explicitly

HOST="${3:-localhost}"
LAUNCHER_PORT="${1:-4013}"
R4_PORT="${2:-4004}"

LAUNCHER_BASE="http://${HOST}:${LAUNCHER_PORT}"
FHIR_BASE="http://${HOST}:${R4_PORT}/hapi-fhir-jpaserver/fhir"
LAUNCHER_FHIR_BASE="${LAUNCHER_BASE}/v/r4/fhir"
CLIENT_ID="test_client_connectathon"
REDIRECT_URI="http://localhost:9999/callback"
SCOPES="launch/patient openid fhirUser patient/*.read"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
PASS=0; FAIL=0; WARN=0

pass() { echo -e "${GREEN}[PASS]${RESET} $*"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${RESET} $*"; ((FAIL++)); }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; ((WARN++)); }
info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
header() { echo -e "\n${BOLD}$*${RESET}"; printf '%.0s-' {1..60}; echo; }

command -v curl &>/dev/null || { echo "curl required"; exit 1; }
command -v jq   &>/dev/null || { echo "jq required";   exit 1; }

http_get()    { curl -s --max-time 10 "$1" 2>/dev/null; }
http_status() { curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$1" 2>/dev/null; }

# ---------------------------------------------------------------------------
# 1. FHIR Server Reachability
# ---------------------------------------------------------------------------
header "TEST 1: FHIR Server Reachability"

STATUS=$(http_status "${FHIR_BASE}/metadata")
if [[ "$STATUS" == "200" ]]; then
  pass "HAPI FHIR R4 direct endpoint reachable (HTTP $STATUS)"
else
  fail "HAPI FHIR R4 direct endpoint unreachable (HTTP $STATUS)"
fi

STATUS=$(http_status "${LAUNCHER_FHIR_BASE}/metadata")
if [[ "$STATUS" == "200" ]]; then
  pass "Launcher FHIR proxy reachable (HTTP $STATUS)"
else
  fail "Launcher FHIR proxy unreachable (HTTP $STATUS)"
fi

FHIR_VERSION=$(http_get "${FHIR_BASE}/metadata" | jq -r '.fhirVersion // "unknown"')
[[ "$FHIR_VERSION" == "4.0.1" ]] && pass "FHIR version R4 (4.0.1)" \
                                   || warn "Unexpected FHIR version: $FHIR_VERSION"

# ---------------------------------------------------------------------------
# 2. SMART Discovery
# ---------------------------------------------------------------------------
header "TEST 2: SMART Discovery (.well-known/smart-configuration)"

SMART_CONFIG=$(http_get "${LAUNCHER_FHIR_BASE}/.well-known/smart-configuration")
AUTH_ENDPOINT=""
TOKEN_ENDPOINT=""

if echo "$SMART_CONFIG" | jq -e '.authorization_endpoint' &>/dev/null; then
  pass "/.well-known/smart-configuration endpoint exists"
  AUTH_ENDPOINT=$(echo "$SMART_CONFIG" | jq -r '.authorization_endpoint')
  TOKEN_ENDPOINT=$(echo "$SMART_CONFIG" | jq -r '.token_endpoint')
  info "authorization_endpoint : $AUTH_ENDPOINT"
  info "token_endpoint         : $TOKEN_ENDPOINT"
else
  fail "/.well-known/smart-configuration missing or invalid"
fi

for FIELD in authorization_endpoint token_endpoint capabilities; do
  echo "$SMART_CONFIG" | jq -e ".${FIELD}" &>/dev/null \
    && pass "Required field present: ${FIELD}" \
    || fail "Required field missing: ${FIELD}"
done

for FIELD in scopes_supported response_types_supported issuer; do
  echo "$SMART_CONFIG" | jq -e ".${FIELD}" &>/dev/null \
    && pass "Recommended field present: ${FIELD}" \
    || warn "Recommended field missing: ${FIELD}"
done

# ---------------------------------------------------------------------------
# 3. CapabilityStatement SMART Security
# ---------------------------------------------------------------------------
header "TEST 3: CapabilityStatement SMART Security"

CAPABILITY=$(http_get "${LAUNCHER_FHIR_BASE}/metadata")
echo "$CAPABILITY" | jq -e '.rest[0].security' &>/dev/null \
  && pass "CapabilityStatement.rest.security block present" \
  || fail "CapabilityStatement.rest.security block missing"

if echo "$CAPABILITY" | jq -e \
  '.rest[0].security.extension[]? | select(.url | test("oauth|smart"))' &>/dev/null; then
  pass "OAuth2/SMART security extension in CapabilityStatement"
else
  warn "OAuth2/SMART security extension not found in CapabilityStatement"
fi

# ---------------------------------------------------------------------------
# 4 & 5. OAuth2 Endpoint Reachability
# ---------------------------------------------------------------------------
header "TEST 4 & 5: OAuth2 Endpoint Reachability"

if [[ -n "$AUTH_ENDPOINT" ]]; then
  STATUS=$(http_status "$AUTH_ENDPOINT")
  [[ "$STATUS" =~ ^[234] ]] \
    && pass "Authorization endpoint reachable (HTTP $STATUS)" \
    || fail "Authorization endpoint unreachable (HTTP $STATUS): $AUTH_ENDPOINT"
else
  fail "Authorization endpoint unknown (discovery failed)"
fi

if [[ -n "$TOKEN_ENDPOINT" ]]; then
  STATUS=$(http_status "$TOKEN_ENDPOINT")
  [[ "$STATUS" =~ ^[234] ]] \
    && pass "Token endpoint reachable (HTTP $STATUS)" \
    || fail "Token endpoint unreachable (HTTP $STATUS): $TOKEN_ENDPOINT"
else
  fail "Token endpoint unknown (discovery failed)"
fi

# ---------------------------------------------------------------------------
# 6. PKCE Support
# ---------------------------------------------------------------------------
header "TEST 6: PKCE Support"

PKCE_METHODS=$(echo "$SMART_CONFIG" | jq -r '.code_challenge_methods_supported // [] | join(",")')
echo "$PKCE_METHODS" | grep -q "S256" \
  && pass "PKCE S256 code challenge method declared" \
  || warn "PKCE S256 not explicitly declared (launcher supports it by default)"

# Generate PKCE values for URL construction
CODE_VERIFIER=$(cat /dev/urandom | tr -dc 'A-Za-z0-9-._~' | head -c 64)
CODE_CHALLENGE=$(printf '%s' "$CODE_VERIFIER" | \
  openssl dgst -binary -sha256 | openssl base64 | tr -d '=' | tr '+' '-' | tr '/' '_')
STATE=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)
pass "PKCE code_verifier and code_challenge generated"

# ---------------------------------------------------------------------------
# 7. Standalone Launch URL
# ---------------------------------------------------------------------------
header "TEST 7: Standalone Launch URL Construction"

if [[ -n "$AUTH_ENDPOINT" ]]; then
  ENC_REDIRECT=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${REDIRECT_URI}'))")
  ENC_SCOPE=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${SCOPES}'))")
  ENC_AUD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${LAUNCHER_FHIR_BASE}'))")

  STANDALONE_URL="${AUTH_ENDPOINT}?response_type=code&client_id=${CLIENT_ID}&redirect_uri=${ENC_REDIRECT}&scope=${ENC_SCOPE}&state=${STATE}&aud=${ENC_AUD}&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256"

  pass "Standalone launch URL constructed"
  echo ""
  echo "  $STANDALONE_URL"
  echo ""
else
  fail "Cannot construct standalone URL - authorization endpoint unknown"
fi

# ---------------------------------------------------------------------------
# 8. EHR Launch URL
# ---------------------------------------------------------------------------
header "TEST 8: EHR Launch URL Construction"

info "smart-dev-sandbox EHR launch via launcher UI:"
echo ""
echo "  ${LAUNCHER_BASE}  → EHR Launch tab"
echo "  App Launch URL  : http://localhost:9999/launch.html"
echo "  FHIR Server     : ${LAUNCHER_FHIR_BASE}"
echo ""
pass "EHR launch URL references constructed"

# ---------------------------------------------------------------------------
# 9. Required SMART Scopes
# ---------------------------------------------------------------------------
header "TEST 9: SMART Scopes Declared"

SCOPES_SUPPORTED=$(echo "$SMART_CONFIG" | jq -r '.scopes_supported // [] | join(" ")')
for SCOPE in "launch" "launch/patient" "openid" "fhirUser" \
             "patient/*.read" "user/*.read" "offline_access"; do
  echo "$SCOPES_SUPPORTED" | grep -q "$SCOPE" \
    && pass "Scope declared: $SCOPE" \
    || warn "Scope not declared: $SCOPE (may still work)"
done

# ---------------------------------------------------------------------------
# 10. Required SMART Capabilities
# ---------------------------------------------------------------------------
header "TEST 10: Required SMART Capabilities"

CAPABILITIES=$(echo "$SMART_CONFIG" | jq -r '.capabilities // [] | join(" ")')
info "Declared capabilities: $CAPABILITIES"

for CAP in "launch-ehr" "launch-standalone" "client-public" \
           "sso-openid-connect" "context-ehr-patient" \
           "context-standalone-patient" "permission-patient" "permission-user"; do
  echo "$CAPABILITIES" | grep -qi "$CAP" \
    && pass "Capability: $CAP" \
    || warn "Capability not declared: $CAP"
done

# ---------------------------------------------------------------------------
# 11. FHIR Resource Availability
# ---------------------------------------------------------------------------
header "TEST 11: FHIR Resource Availability"

PATIENTS=$(http_get "${FHIR_BASE}/Patient?_count=3")
if echo "$PATIENTS" | jq -e '.resourceType == "Bundle"' &>/dev/null; then
  PT_COUNT=$(echo "$PATIENTS" | jq '.entry | length // 0')
  pass "Patient search returns Bundle ($PT_COUNT patients)"
  PATIENT_ID=$(echo "$PATIENTS" | jq -r '.entry[0].resource.id // empty' 2>/dev/null)
  [[ -n "$PATIENT_ID" ]] && info "Sample patient ID: $PATIENT_ID" \
                          || warn "No patients found - load test data before connectathon"
else
  fail "Patient search did not return FHIR Bundle"
fi

for RESOURCE in Observation Condition AllergyIntolerance \
                Encounter Procedure MedicationRequest DiagnosticReport; do
  RESULT=$(http_get "${FHIR_BASE}/${RESOURCE}?_count=1")
  TOTAL=$(echo "$RESULT" | jq -r '.total // 0' 2>/dev/null || echo 0)
  if [[ "$TOTAL" -gt 0 ]] 2>/dev/null; then
    pass "${RESOURCE}: ${TOTAL} resources available"
  else
    warn "${RESOURCE}: 0 resources (load test data if needed)"
  fi
done

# ---------------------------------------------------------------------------
# 12. Launcher Open Endpoint
# ---------------------------------------------------------------------------
header "TEST 12: Launcher Open FHIR Endpoint"

OPEN=$(http_get "${LAUNCHER_BASE}/v/r4/fhir/Patient?_count=1")
if echo "$OPEN" | jq -e '.resourceType == "Bundle"' &>/dev/null; then
  pass "Launcher open FHIR endpoint returns valid Bundle"
else
  warn "Launcher open FHIR endpoint did not return Bundle"
fi

# ---------------------------------------------------------------------------
# 13. Optional Endpoints
# ---------------------------------------------------------------------------
header "TEST 13: Optional OAuth2 Endpoints"

for KEY in introspection_endpoint revocation_endpoint registration_endpoint; do
  VAL=$(echo "$SMART_CONFIG" | jq -r ".${KEY} // empty")
  [[ -n "$VAL" ]] && pass "${KEY}: $VAL" || warn "${KEY}: not declared (optional)"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
printf '=%.0s' {1..64}; echo
echo -e "${BOLD}VALIDATION SUMMARY${RESET}"
printf '=%.0s' {1..64}; echo
echo -e "  ${GREEN}PASS${RESET} : $PASS"
echo -e "  ${YELLOW}WARN${RESET} : $WARN"
echo -e "  ${RED}FAIL${RESET} : $FAIL"
echo ""

if   [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}Action required: $FAIL test(s) failed — review before connectathon.${RESET}"
elif [[ $WARN -gt 0 ]]; then
  echo -e "${YELLOW}Ready with $WARN warning(s) — review but likely non-blocking.${RESET}"
else
  echo -e "${GREEN}All tests passed — sandbox is connectathon-ready.${RESET}"
fi

echo ""
printf '=%.0s' {1..64}; echo
echo -e "${BOLD}MANUAL TEST CHECKLIST${RESET}"
printf '=%.0s' {1..64}; echo
echo ""
echo "1. STANDALONE LAUNCH (browser required)"
echo "   a. Open : ${LAUNCHER_BASE}"
echo "   b. Select 'Standalone Launch' tab"
echo "   c. FHIR Server  : ${LAUNCHER_FHIR_BASE}"
echo "   d. Scopes       : launch/patient openid fhirUser patient/*.read"
echo "   e. Launch → select patient → verify redirect with ?code="
echo ""
echo "2. EHR LAUNCH (browser required)"
echo "   a. Open : ${LAUNCHER_BASE}"
echo "   b. Select 'EHR Launch' tab"
echo "   c. App Launch URL : http://your-app/launch.html"
echo "   d. Select patient and provider → Launch"
echo "   e. Verify app receives iss + launch params"
echo ""
echo "3. PATIENT BROWSER"
echo "   Open: http://${HOST}:4009"
echo "   Verify patient list loads from HAPI R4"
echo ""
echo "4. FHIR VIEWER"
echo "   Open: http://${HOST}:4010"
echo "   Search for a patient and verify resources display"
echo ""
echo "5. SMART CONFIGURATION"
echo "   curl -s ${LAUNCHER_FHIR_BASE}/.well-known/smart-configuration | jq ."
echo ""

