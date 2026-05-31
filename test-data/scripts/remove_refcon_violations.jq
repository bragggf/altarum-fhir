# Step 1: Remove dangling ServiceRequest and Observation references
. as $bundle |
($bundle.entry | map(.resource | select(.id != null) | .resourceType + "/" + (.id | tostring))) as $valid_ids |
$bundle |
walk(
  if type == "array" then
    map(
      if type == "object" and .reference? != null then
        select(
          (.reference | test("^ServiceRequest/|^Observation/cancer") | not) or
          (.reference | IN($valid_ids[]))
        )
      else .
      end
    )
  elif type == "object" and .reference? != null then
    if (.reference | test("^ServiceRequest/|^Observation/cancer")) and
       (.reference | IN($valid_ids[]) | not) then
      empty
    else .
    end
  else .
  end
) |
# Step 2: Remove empty arrays left after reference removal 
walk( 
  if type == "object" then 
     with_entries( 
       if (.key | IN("basedOn","assessment","profile","performer","reasonReference","supportingInfo")) and (.value | type) == "array" and (.value | length) == 0 then 
         empty 
       else . 
       end 
    ) 
  else . end 
)


