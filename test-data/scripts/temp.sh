bash

python3 - << 'EOF'
import jq, json

# All three condition fixes now work. 
# Now write the complete corrected script using:
# 1. // operator for all simple null-default assignments (EOB, Claim, Coverage, MedReq, Procedure)
# 2. Direct .resource.field path assignments for Condition (avoids nested |= pipe issue)

SCRIPT = r'''
.entry |= map(

  # ── ExplanationOfBenefit ──────────────────────────────────────────────────
  if .resource.resourceType == "ExplanationOfBenefit" then
    .resource |= (. + {
      use:      (.use      // "claim"),
      outcome:  (.outcome  // "complete"),
      created:  (.created  // "1970-01-01T00:00:00Z"),
      provider: (.provider // {"display": "Unknown"}),
      insurer:  (.insurer  // {"display": "Unknown"})
    }) |
    if (.resource.insurance | type) == "array" then
      .resource.insurance |= map(. + {focal: (.focal // true)})
    else . end |
    if (.resource.total | type) == "array" then
      .resource.total |= map(
        if .amount == null then
          . + {amount: {"value": 0, "currency": "USD"}}
        else . end)
    else . end

  # ── Claim ─────────────────────────────────────────────────────────────────
  elif .resource.resourceType == "Claim" then
    .resource |= (. + {
      priority: (.priority // {"coding": [{"code": "normal"}]}),
      created:  (.created  // "1970-01-01T00:00:00Z"),
      provider: (.provider // {"display": "Unknown"})
    }) |
    if (.resource.item | type) == "array" then
      .resource.item |= map(. + {
        productOrService: (.productOrService // {
          "coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/data-absent-reason",
            "code":   "unknown"
          }]
        })
      })
    else . end

  # ── Coverage ──────────────────────────────────────────────────────────────
  elif .resource.resourceType == "Coverage" then
    .resource |= (. + {
      status: (.status // "active"),
      payor:  (.payor  // [{"display": "Unknown"}])
    })

  # ── MedicationRequest ─────────────────────────────────────────────────────
  elif .resource.resourceType == "MedicationRequest" then
    .resource |= (. + {
      status: (.status // "active"),
      intent: (.intent // "order")
    }) |
    if .resource.medicationCodeableConcept == null and
       .resource.medicationReference == null then
      .resource.medicationCodeableConcept = {
        "coding": [{
          "system": "http://terminology.hl7.org/CodeSystem/data-absent-reason",
          "code":   "unknown"
        }]
      }
    else . end

  # ── Procedure ─────────────────────────────────────────────────────────────
  elif .resource.resourceType == "Procedure" then
    .resource |= (. + {status: (.status // "unknown")})

  # ── Condition ─────────────────────────────────────────────────────────────
  # Use direct path assignments (not nested |= chains) to avoid jq pipe
  # scoping issue where intermediate updates get dropped
  elif .resource.resourceType == "Condition" then
    (if (.resource.clinicalStatus.coding | type) == "array" then
       .resource.clinicalStatus.coding |= map(
         .system = "http://terminology.hl7.org/CodeSystem/condition-clinical")
     else . end) |
    (if (.resource.verificationStatus.coding | type) == "array" then
       .resource.verificationStatus.coding |= map(
         .system = "http://terminology.hl7.org/CodeSystem/condition-ver-status")
     else . end) |
    (if (.resource.category | type) == "array" then
       .resource.category |= map(
         if (.coding | type) == "array" then
           .coding |= map(
             if .system == "http://hl7.org/fhir/ValueSet/condition-category" then
               .system = "http://terminology.hl7.org/CodeSystem/condition-category"
             else . end)
         else . end)
     else . end) |
    (if .resource.abatement != null then
       .resource.clinicalStatus.coding[0].code = "resolved"
     else . end)

  else . end

) |

# ── Strip mihin copyright extensions from entire bundle ───────────────────
walk(
  if type == "array" then
    map(select(
      type != "object" or
      (.url? != "http://mihin.org/extension/copyright")
    ))
  else . end
)
'''

with open("/home/claude/fix_bundle.jq", "w") as f:
    f.write(SCRIPT)

# Full comprehensive test
test_bundle = {
  "entry": [
    # EOB: all nulls + arrays needing fixes
    {"resource": {"resourceType": "ExplanationOfBenefit", "id": "eob1",
      "use": None, "outcome": None, "created": None, "provider": None, "insurer": None,
      "insurance": [{"coverage": {"reference": "Coverage/1"}}],
      "total": [{"category": {"coding": [{"code": "submitted"}]}}]
    }},
    # EOB: completely empty (all missing)
    {"resource": {"resourceType": "ExplanationOfBenefit", "id": "eob2"}},
    # Claim: null item array
    {"resource": {"resourceType": "Claim", "id": "claim1",
      "priority": None, "created": None, "provider": None, "item": None}},
    # Claim: items with mix of present/missing productOrService
    {"resource": {"resourceType": "Claim", "id": "claim2",
      "item": [{"sequence": 1}, {"sequence": 2, "productOrService": {"coding": [{"code": "keep"}]}}]
    }},
    # Coverage: null fields
    {"resource": {"resourceType": "Coverage", "id": "cov1", "status": None, "payor": None}},
    # MedicationRequest: null fields, no medication
    {"resource": {"resourceType": "MedicationRequest", "id": "med1",
      "status": None, "intent": None,
      "medicationCodeableConcept": None, "medicationReference": None}},
    # Procedure: null status
    {"resource": {"resourceType": "Procedure", "id": "proc1", "status": None}},
    # Condition: abatement present, old systems
    {"resource": {"resourceType": "Condition", "id": "cond1",
      "abatement": "2020-01-01",
      "clinicalStatus": {"coding": [{"system": "old", "code": "active"}]},
      "verificationStatus": {"coding": [{"system": "old", "code": "confirmed"}]},
      "category": [{"coding": [{"system": "http://hl7.org/fhir/ValueSet/condition-category", "code": "ec"}]}]
    }},
    # Condition: no abatement, null codings
    {"resource": {"resourceType": "Condition", "id": "cond2",
      "clinicalStatus": {"coding": None},
      "verificationStatus": {"coding": None},
      "category": None
    }},
    # Patient: mihin extension should be stripped, valid kept
    {"resource": {"resourceType": "Patient", "id": "pat1",
      "extension": [
        {"url": "http://mihin.org/extension/copyright", "valueString": "c"},
        {"url": "http://hl7.org/fhir/valid-ext", "valueString": "keep"}
      ]
    }},
    # Non-affected resource: should pass through unchanged
    {"resource": {"resourceType": "Organization", "id": "org1", "name": "Test Org"}},
  ]
}

result = jq.first(SCRIPT, test_bundle)
all_pass = True
print("=== TEST RESULTS ===\n")

for e in result["entry"]:
    r = e["resource"]
    rt, rid = r["resourceType"], r["id"]
    issues = []

    if rt == "ExplanationOfBenefit":
        for f in ["use","outcome","created","provider","insurer"]:
            if r.get(f) is None: issues.append(f"FAIL: {f} still null")
        if r.get("insurance") and not r["insurance"][0].get("focal"):
            issues.append("FAIL: insurance.focal not set")
        if r.get("total") and not r["total"][0].get("amount"):
            issues.append("FAIL: total.amount not set")
    elif rt == "Claim":
        for f in ["priority","created","provider"]:
            if r.get(f) is None: issues.append(f"FAIL: {f} still null")
        if r.get("item"):
            for i in r["item"]:
                if not i.get("productOrService"): issues.append("FAIL: item.productOrService null")
    elif rt == "Coverage":
        if not r.get("status"): issues.append("FAIL: status null")
        if not r.get("payor"):  issues.append("FAIL: payor null")
    elif rt == "MedicationRequest":
        if not r.get("status"): issues.append("FAIL: status null")
        if not r.get("intent"): issues.append("FAIL: intent null")
        if not r.get("medicationCodeableConcept") and not r.get("medicationReference"):
            issues.append("FAIL: no medication")
    elif rt == "Procedure":
        if not r.get("status"): issues.append("FAIL: status null")
    elif rt == "Condition":
        if rid == "cond1":
            cs = r.get("clinicalStatus",{}).get("coding",[{}])[0]
            vs = r.get("verificationStatus",{}).get("coding",[{}])[0]
            cat = (r.get("category",[{}])[0].get("coding",[{}])[0])
            if "terminology.hl7.org" not in cs.get("system",""): issues.append(f"FAIL: clinicalStatus system not updated: {cs.get('system')}")
            if cs.get("code") != "resolved": issues.append(f"FAIL: clinicalStatus code not resolved: {cs.get('code')}")
            if "terminology.hl7.org" not in vs.get("system",""): issues.append(f"FAIL: verificationStatus system not updated: {vs.get('system')}")
            if "terminology.hl7.org" not in cat.get("system",""): issues.append(f"FAIL: category system not updated: {cat.get('system')}")
    elif rt == "Patient":
        exts = [x["url"] for x in r.get("extension",[])]
        if "http://mihin.org/extension/copyright" in exts: issues.append("FAIL: mihin ext not stripped")
        if "http://hl7.org/fhir/valid-ext" not in exts: issues.append("FAIL: valid ext stripped")

    status = "PASS" if not issues else "FAIL"
    if issues: all_pass = False
    print(f"  [{status}] {rt}/{rid}")
    for i in issues:
        print(f"         {i}")

print(f"\n{'ALL TESTS PASSED' if all_pass else 'SOME TESTS FAILED'}")
EOF
Output

=== TEST RESULTS ===

  [PASS] ExplanationOfBenefit/eob1
  [PASS] ExplanationOfBenefit/eob2
  [PASS] Claim/claim1
  [PASS] Claim/claim2
  [PASS] Coverage/cov1
  [PASS] MedicationRequest/med1
  [PASS] Procedure/proc1
  [PASS] Condition/cond1
  [PASS] Condition/cond2
  [PASS] Patient/pat1
  [PASS] Organization/org1

ALL TESTS PASSED
Done

