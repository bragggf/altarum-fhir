# Load with full response capture
for chunk in ./split_bundles/chunk_*.json; do
    echo "Loading $chunk..."
    response=$(curl -s -X POST \
      http://localhost:4004/hapi-fhir-jpaserver/fhir \
      -H "Content-Type: application/fhir+json" \
      -H "Prefer: return=OperationOutcome" \
      --max-time 300 \
      --data @"$chunk")
    
    status=$(echo "$response" | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
    issues = [i for i in data.get('issue',[]) if i['severity']=='error']
    if issues:
        for i in issues[:3]:
            print('ERROR: ' + i.get('diagnostics','')[:100])
    else:
        print('OK')
except:
    print('PARSE ERROR')
" 2>/dev/null)
    
    echo "  $status"
done
