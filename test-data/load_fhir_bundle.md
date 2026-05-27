# Basic (defaults to http://localhost:8080/fhir)
./load_fhir_bundle.sh patient_bundle.json

# Custom server URL as argument
./load_fhir_bundle.sh patient_bundle.json https://my-hapi-server.com/fhir

# Or via environment variable
FHIR_BASE_URL=https://my-hapi-server.com/fhir ./load_fhir_bundle.sh patient_bundle.json

Pre-flight validation — checks the file exists, curl is installed, and (if jq is available) verifies the JSON is a FHIR Bundle resource before sending anything
Correct FHIR headers — uses Content-Type: application/fhir+json and Accept: application/fhir+json as required by HAPI FHIR
Pretty-printed response — uses jq to format the server's response bundle if available
Per-entry status codes — extracts and lists each entry's response status from the transaction response
HTTP status handling — distinct error messages for 400, 401/403, 404, and 422 (validation failure)
Configurable timeout — defaults to 60 seconds, easy to adjust at the top of the script

Tip: For large bundles or servers requiring auth, you can add a bearer token by appending --header "Authorization: Bearer $TOKEN" to the CURL_OPTS array.

