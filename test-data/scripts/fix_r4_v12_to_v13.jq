walk(
  if type == "object" and has("extension") then
    if .extension == null or
       ((.extension | type) == "array" and (.extension | length) == 0) then
      del(.extension)
    else .
    end
  else .
  end
)

