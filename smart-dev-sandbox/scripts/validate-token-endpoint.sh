
PORT=4013

# get is not supported on auth token.  will return 404
# curl -v http://localhost:${PORT}/v/r4/auth/token 2>&1 | head -20

# Compare with what the launcher actually serves:
curl -s http://localhost:${PORT}/v/r4/fhir/.well-known/smart-configuration | jq '.token_endpoint'

curl -s -X POST http://localhost:{PORT}/v/r4/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&code=invalid_test_code&redirect_uri=http://localhost:9999/callback" \
  | jq .

