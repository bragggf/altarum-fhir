
curl -s -G "http://localhost:8080/fhir/ValueSet/\$expand" \
  --data-urlencode "url=http://hl7.org/fhir/us/core/ValueSet/omb-race-category" \
  | jq '.expansion.total'

curl -s -G "http://localhost:8080/fhir/ValueSet/\$expand" \
  --data-urlencode "url=http://hl7.org/fhir/us/core/ValueSet/omb-ethnicity-category" \
  | jq '.expansion.total'

curl -s -G "http://localhost:8080/fhir/ValueSet/\$expand" \
  --data-urlencode "url=http://hl7.org/fhir/us/core/ValueSet/birthsex" \
  | jq '.expansion.total'

