#!/usr/bin/env python3
"""
fix_helios_bundle.py
Fixes all data quality issues in the Helios FHIR R4 batch bundle.

Usage:
    python3 fix_helios_bundle.py test-data.json test-data-helios-fixed.json

Fixes applied (32 total):
    1.  Add absolute fullUrl to all entries
    2.  Remove meta.source #fragment references
    3.  Claim required R4 fields (created, priority, insurance.focal, procedure.procedure[x])
    4.  MedicationRequest.intent
    5.  Account.coverage.coverage
    6.  Family Planning invalid resource type in Encounter
    7.  Remove patient-birthTime extensions with no value (resource.extension)
    8.  ext-1 answerOption - remove extension when valueCoding also present
    9.  Local/invalid coding systems (Detected, Normal, www.cap.org/eCC)
    10. Null literal codes (string "null")
    11. DL display name
    12. Remove LOINC and SNOMED display names
    13. J1100 trailing space
    14. issued date-only on DiagnosticReport/Observation
    15. Posiive typo
    16. JMC system URI
    17. us-core-race/ethnicity valueCodeableConcept to sub-extensions
    18. race/ethnicity wrong CodeSystem OID
    19. us-core-2 Observation with no value
    20. Specimen missing type
    21. Unknown LOINC codes (7+ digit numeric)
    22. Unknown SNOMED codes
    23. Identifier.system not absolute URI
    24. Remove unverifiable profiles
    25. Add narrative to resources missing it
    26. Remove null issued and null extension (combined walk - must be last)
    27. Claim.priority coding missing system
    28. Remove Coding objects with JSON null code
    29. Remove patient-birthTime extensions with no value from _birthDate
    30. Remove empty arrays (coding, identifier, telecom, etc.)
    31. Remove patient-birthTime with no value from _birthDate.extension
    32. Fix us-core-birthsex sub-extension structure -> valueCode
"""

import sys
import json
import subprocess
import copy
import re
import os

FHIR_BASE = "http://localhost:4004/hapi-fhir-jpaserver/fhir"

JQ_SCRIPT = r"""
.entry |= map(
  if has("fullUrl") then .
  elif (.resource.id != null) then
    . + {fullUrl: ("FHIR_BASE_PLACEHOLDER/" + .resource.resourceType + "/" + (.resource.id | tostring))}
  else . end
) |
walk(if type == "object" and .source? != null and (.source | type) == "string" and (.source | startswith("#")) then del(.source) else . end) |
.entry |= map(
  if .resource.resourceType == "Claim" then
    .resource |= (. + {created: (.created // "1970-01-01T00:00:00Z"), priority: (.priority // {"coding": [{"code": "normal"}]})}) |
    (if (.resource.insurance | type) == "array" then .resource.insurance |= map(. + {focal: (.focal // true)}) else . end) |
    (if (.resource.procedure | type) == "array" then .resource.procedure |= map(if .procedureCodeableConcept == null and .procedureReference == null then . + {procedureCodeableConcept: {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason", "code": "unknown"}]}} else . end) else . end)
  else . end
) |
.entry |= map(if .resource.resourceType == "MedicationRequest" and .resource.intent == null then .resource.intent = "order" else . end) |
.entry |= map(if .resource.resourceType == "Account" and (.resource.coverage | type) == "array" then .resource.coverage |= map(if .coverage == null then . + {coverage: {"display": "Unknown"}} else . end) else . end) |
.entry |= map(
  if .resource.resourceType == "Encounter" then
    (if .resource.class.display? == "Family Planning" then .resource.class = {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "AMB", "display": "ambulatory"} else . end) |
    (if .resource.subject.type? == "Family Planning" then .resource.subject |= del(.type) else . end)
  else . end
) |
.entry |= map(if .resource != null and (.resource.extension | type) == "array" then .resource.extension |= map(select(type != "object" or (.url? | strings | contains("patient-birthTime") | not) or (.valueDateTime != null))) else . end) |
.entry |= map(if .resource != null then walk(if type == "object" and has("valueCoding") and has("extension") and (.url == null or (has("url") | not)) then del(.extension) else . end) else . end) |
walk(if type == "object" and has("system") and has("code") then if .system == "Detected" or .system == "Normal" then .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" | .code = "unknown" | del(.display) elif .system == "www.cap.org/eCC" then .system = "urn:local:www.cap.org/eCC" else . end else . end) |
walk(if type == "object" and (.code? | type) == "string" and .code == "null" then .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" | .code = "unknown" else . end) |
walk(if type == "object" and .system? == "http://terminology.hl7.org/CodeSystem/v2-0203" and .code? == "DL" then del(.display) else . end) |
walk(if type == "object" and .display? != null then if .system? == "http://loinc.org" or .system? == "http://snomed.info/sct" then del(.display) else . end else . end) |
walk(if type == "string" and . == "J1100 " then "J1100" else . end) |
.entry |= map(if .resource.resourceType == "DiagnosticReport" or .resource.resourceType == "Observation" then .resource.issued |= (if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") then . + "T00:00:00Z" else . end) else . end) |
walk(if type == "string" and contains("Posiive") then gsub("Posiive"; "Positive") else . end) |
walk(if type == "object" and .system? == "JMC system" then .system = "urn:local:JMC-system" else . end) |
.entry |= map(
  if .resource.resourceType == "Patient" then
    .resource.extension |= (if type == "array" then map(
      if (.url | contains("us-core-race")) and .valueCodeableConcept != null then
        {"url": .url, "extension": ([{"url": "ombCategory", "valueCoding": .valueCodeableConcept.coding[0]}, {"url": "text", "valueString": (.valueCodeableConcept.text // .valueCodeableConcept.coding[0].display // "Unknown")}] | map(select(.valueCoding != null or .valueString != null)))}
      elif (.url | contains("us-core-ethnicity")) and .valueCodeableConcept != null then
        {"url": .url, "extension": ([{"url": "ombCategory", "valueCoding": .valueCodeableConcept.coding[0]}, {"url": "text", "valueString": (.valueCodeableConcept.text // .valueCodeableConcept.coding[0].display // "Unknown")}] | map(select(.valueCoding != null or .valueString != null)))}
      else . end) else . end)
  else . end
) |
walk(if type == "object" and (.system? == "http://terminology.hl7.org/CodeSystem/v3-Race" or .system? == "http://terminology.hl7.org/CodeSystem/v3-Ethnicity") then .system = "urn:oid:2.16.840.1.113883.6.238" else . end) |
.entry |= map(if .resource.resourceType == "Observation" and .resource.valueQuantity == null and .resource.valueCodeableConcept == null and .resource.valueString == null and .resource.valueBoolean == null and .resource.valueInteger == null and .resource.dataAbsentReason == null and (.resource.component == null or (.resource.component | length) == 0) and (.resource.hasMember == null or (.resource.hasMember | length) == 0) then .resource.dataAbsentReason = {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason", "code": "unknown", "display": "Unknown"}]} else . end) |
.entry |= map(if .resource.resourceType == "Specimen" and .resource.type == null then .resource.type = {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/data-absent-reason", "code": "unknown"}]} else . end) |
walk(if type == "object" and .system? == "http://loinc.org" and (.code? | strings | test("^[0-9]{7,}$")) then .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" | .code = "unknown" else . end) |
walk(if type == "object" and .system? == "http://snomed.info/sct" and (.code? | IN("36929009", "72300004", "433466002")) then .system = "http://terminology.hl7.org/CodeSystem/data-absent-reason" | .code = "unknown" else . end) |
walk(if type == "object" and has("system") and has("value") and .system != null and (.system | type) == "string" and (.system | (startswith("http") or startswith("urn:") or startswith("oid:") or . == "phone" or . == "email" or . == "fax" or . == "url" or . == "sms" or . == "pager" or . == "other") | not) then .system = ("urn:local:" + .system) else . end) |
.entry |= map(if (.resource.meta.profile | type) == "array" then .resource.meta.profile |= map(select((contains("cancer-reporting") | not) and (contains("sdc-") | not) and (contains("sdoh") | not) and (contains("3.1.1") | not) and (contains("STU7") | not))) else . end) |
.entry |= map(if .resource != null and (.resource | has("resourceType")) and (.resource.text == null or .resource.text.div == null) then .resource.text = {"status": "generated", "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>Narrative not available</p></div>"} else . end) |
walk(if type == "object" then (if has("issued") and .issued == null then del(.issued) else . end) | (if has("extension") and .extension == null then del(.extension) else . end) else . end) |
.entry |= map(if .resource.resourceType == "Claim" and (.resource.priority.coding | type) == "array" then .resource.priority.coding |= map(if .system == null then . + {"system": "http://terminology.hl7.org/CodeSystem/processpriority"} else . end) else . end) |
walk(if type == "array" then map(select(type != "object" or has("value") or .code != null or (has("system") | not))) else . end) |
.entry |= map(if .resource.resourceType == "Patient" and (.resource._birthDate | type) == "object" and (.resource._birthDate.extension | type) == "array" and (.resource._birthDate.extension | length) == 0 then .resource._birthDate |= del(.extension) else . end) |
walk(if type == "object" then with_entries(if (.value | type) == "array" and (.value | length) == 0 and (.key | IN("coding","identifier","telecom","performer","category","interpretation","note","bodySite","method","specimen","device","referenceRange","hasMember","derivedFrom","component","modifier","programCode","subSite","adjudication","detail","onAdmission")) then empty else . end) else . end) |
.entry |= map(if .resource.resourceType == "Patient" and (.resource._birthDate | type) == "object" and (.resource._birthDate.extension | type) == "array" then .resource._birthDate.extension |= map(select(type != "object" or (.url? | strings | contains("patient-birthTime") | not) or (keys | map(select(. != "url")) | length > 0))) else . end) |
walk(if type == "object" then (if has("issued") and .issued == null then del(.issued) else . end) | (if has("extension") and .extension == null then del(.extension) else . end) else . end)
"""

def fix_birthsex(data):
    """Fix us-core-birthsex sub-extension structure -> valueCode"""
    for entry in data.get("entry", []):
        resource = entry.get("resource", {})
        if resource.get("resourceType") != "Patient":
            continue
        extensions = resource.get("extension")
        if not isinstance(extensions, list):
            continue
        new_exts = []
        for ext in extensions:
            url = ext.get("url", "")
            if "us-core-birthsex" in url and "valueCode" not in ext:
                sub_exts = ext.get("extension", [])
                if isinstance(sub_exts, list):
                    code = "UNK"
                    for sub in sub_exts:
                        if sub.get("url") == "value":
                            code = sub.get("valueCode") or \
                                   ((sub.get("valueCodeableConcept") or {})
                                    .get("coding", [{}])[0].get("code")) or "UNK"
                            break
                    new_exts.append({"url": url, "valueCode": code})
                    continue
            new_exts.append(ext)
        resource["extension"] = new_exts
    return data


def main():
    if len(sys.argv) < 3:
        print(f"Usage: python3 {sys.argv[0]} input.json output.json")
        print(f"       FHIR_BASE env var overrides default: {FHIR_BASE}")
        sys.exit(1)

    input_file  = sys.argv[1]
    output_file = sys.argv[2]
    fhir_base   = os.environ.get("FHIR_BASE", FHIR_BASE)

    print(f"Reading  : {input_file}")
    with open(input_file) as f:
        bundle = json.load(f)

    entry_count = len(bundle.get("entry", []))
    print(f"Entries  : {entry_count}")

    # Step 1: Apply jq fixes
    jq_script = JQ_SCRIPT.replace("FHIR_BASE_PLACEHOLDER", fhir_base)
    print("Applying jq fixes...")
    proc = subprocess.run(
        ["jq", "-c", jq_script],
        input=json.dumps(bundle).encode(),
        capture_output=True
    )
    if proc.returncode != 0:
        print(f"jq error: {proc.stderr.decode()}")
        sys.exit(1)
    bundle = json.loads(proc.stdout)

    # Step 2: Apply Python fix (birthsex sub-extension)
    print("Applying Python fixes (birthsex)...")
    bundle = fix_birthsex(bundle)

    # Verify
    final_count = len(bundle.get("entry", []))
    if final_count != entry_count:
        print(f"WARNING: Entry count changed {entry_count} -> {final_count}")
    else:
        print(f"Entry count OK: {final_count}")

    print(f"Writing  : {output_file}")
    with open(output_file, "w") as f:
        json.dump(bundle, f)

    print("Done.")


if __name__ == "__main__":
    main()

