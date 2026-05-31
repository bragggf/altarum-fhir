

jq '
  # Remove # fragment references from meta.source
  walk(
    if type == "object" and .source? != null and (.source | startswith("#")) then
      del(.source)
    else . end
  ) |
  # Remove any reference fields pointing to # fragments that have no matching contained resource
  .entry |= map(
    if .resource.contained == null or (.resource.contained | length) == 0 then
      walk(
        if type == "object" and .reference? != null and (.reference | startswith("#")) then
          del(.reference)
        else . end
      )
    else . end
  )
' clean_cdc_bundle.json > clean_cdc_final_v2.json


jq ' # Remove # fragment references from meta.source walk( if type == "object" and .source? != null and (.source | startswith("#")) then del(.source) else . end ) | # Remove any reference fields pointing to # fragments that have no matching contained resource .entry |= map( if .resource.contained == null or (.resource.contained | length) == 0 then walk( if type == "object" and .reference? != null and (.reference | startswith("#")) then del(.reference) else . end ) else . end ) '



