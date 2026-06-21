#!/usr/bin/env python3
"""
fix_bundle.py  — v3
Fixes HAPI FHIR 8.8.0 validation errors in FHIR R4 batch bundles.
Handles Helios, MIMIC and general dataset issues.

Usage:
    python3 fix_bundle.py input.json output.json
    FHIR_BASE=http://helios-connect.immunization-registries.org:4004/hapi-fhir-jpaserver/fhir \
        python3 fix_bundle.py input.json output.json
"""

import sys, json, copy, re, os

FHIR_BASE = os.environ.get("FHIR_BASE",
    "http://localhost:4004/hapi-fhir-jpaserver/fhir")

DAR = "http://terminology.hl7.org/CodeSystem/data-absent-reason"
NARRATIVE = '<div xmlns="http://www.w3.org/1999/xhtml"><p>Narrative not available</p></div>'

UNKNOWN_SYSTEMS = {
    # MIMIC
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-medication-formulary-drug-cd",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-medication-gsn",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-lab-fluid",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-medication-ndc",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-medication-name",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-medication-etc",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-medication-icu",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-lab-category",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-lab-itemid",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-observation-category",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-diagnosis-icd_version",
    "http://mimic.mit.edu/fhir/mimic/CodeSystem/mimic-procedure-category",
    # NDC / External
    "https://ndclist.com",
    "https://www.nubc.org/CodeSystem/RevenueCodes",
    "https://www.cms.gov/Medicare/Coding/HCPCSReleaseCodeSets",
    "https://fhir.cerner.com",
    "http://smarthealthit.org",
    "https://cap.org", "http://cap.org",
    "http://id.who.int/icd",
    "https://example.org",
    "https://clinicaltables.nlm.nih.gov",
}

UNKNOWN_PREFIXES = (
    "http://mimic.mit.edu/",
    "https://www.nubc.org/",
    "https://www.cms.gov/Medicare/",
    "https://fhir.cerner.com/",
    "http://smarthealthit.org/",
    "https://cap.org/", "http://cap.org/",
    "http://id.who.int/",
    "https://example.org/",
    "https://clinicaltables.nlm.nih.gov/",
    "http://hl7.org/fhir/us/sdoh-clinicalcare/CodeSystem/",
    "http://hl7.org/fhir/us/cancer-reporting/CodeSystem/",
    "https://dev-gw.interop.community/",
    "https://dev-jtx41.devinteropland.com/",
)

EMPTY_ARRAY_FIELDS = {
    "coding","identifier","telecom","performer","category",
    "interpretation","note","bodySite","method","specimen",
    "device","referenceRange","hasMember","derivedFrom",
    "component","modifier","programCode","subSite",
    "adjudication","detail","onAdmission",
}

# LOINC codes whose display names HAPI validates strictly - just remove display
LOINC_REMOVE_DISPLAY = {
    "8310-5",  # Body temperature
    "3141-9",  # Body weight
    "8867-4",  # Heart rate
    "9279-1",  # Respiratory rate
    "55284-4", # Blood pressure
    "8480-6",  # Systolic BP
    "8462-4",  # Diastolic BP
    "59408-5", # SpO2
    "8302-2",  # Body height
    "2710-2",  # Oxygen saturation
    "29463-7", # Body weight (alternate)
    "8287-5",  # Head circumference
    "39156-5", # BMI
}


def is_unknown_system(system):
    if not isinstance(system, str):
        return False
    if system in UNKNOWN_SYSTEMS:
        return True
    return any(system.startswith(p) for p in UNKNOWN_PREFIXES)


def fix_object(obj):
    """Recursively fix all issues. Modifies in place."""
    if isinstance(obj, dict):

        # Fix: meta.source #fragment
        if "source" in obj and isinstance(obj.get("source"), str) \
                and obj["source"].startswith("#"):
            del obj["source"]

        # Fix: text inside Coding object
        # Only delete "text" if this looks like a Coding (not a resource/extension)
        CODING_KEYS = {"system","code","display","version","userSelected","text"}
        if ("system" in obj or "code" in obj) \
                and "coding" not in obj \
                and "text" in obj \
                and "div" not in obj \
                and "resourceType" not in obj \
                and "url" not in obj \
                and "value" not in obj \
                and set(obj.keys()) <= CODING_KEYS:
            del obj["text"]

        # Fix: compound system URLs (comma-separated multiple systems)
        if "system" in obj and isinstance(obj.get("system"), str) and \
                "," in obj["system"]:
            obj["system"] = DAR
            obj["code"] = "unknown"
            obj.pop("display", None)

        # Fix: null code with system present (Coding with no code)
        if "system" in obj and isinstance(obj.get("system"), str) and \
                "code" in obj and obj["code"] is None and \
                "value" not in obj:
            obj["system"] = DAR
            obj["code"] = "unknown"
            obj.pop("display", None)

        # Fix: URI whitespace
        for field in ("system", "url"):
            if field in obj and isinstance(obj.get(field), str) \
                    and " " in obj[field]:
                obj[field] = obj[field].replace(" ", "-")

        # Fix: unknown external CodeSystems
        if "system" in obj and "code" in obj \
                and isinstance(obj.get("system"), str) \
                and isinstance(obj.get("code"), str) \
                and is_unknown_system(obj["system"]):
            obj["system"] = DAR
            obj["code"] = "unknown"
            obj.pop("display", None)

        # Fix: null literal code in ex-diagnosis-on-admission and modifiers
        if obj.get("system") in (
                "http://terminology.hl7.org/CodeSystem/ex-diagnosis-on-admission",
                "http://terminology.hl7.org/CodeSystem/modifiers") \
                and obj.get("code") in ("null", None):
            obj["system"] = DAR
            obj["code"] = "unknown"
            obj.pop("display", None)

        # Fix: ANY string "null" code in any CodeSystem
        if isinstance(obj.get("code"), str) and obj["code"] == "null" \
                and isinstance(obj.get("system"), str):
            obj["system"] = DAR
            obj["code"] = "unknown"
            obj.pop("display", None)

        # Fix: snomed.info missing /sct
        if obj.get("system") == "http://snomed.info":
            obj["system"] = "http://snomed.info/sct"

        # Fix: referencerange-meaning wrong URL
        if obj.get("system") == "http://hl7.org/fhir/referencerange-meaning":
            obj["system"] = \
                "http://terminology.hl7.org/CodeSystem/referencerange-meaning"

        # Fix: UCUM annotation {xxx}
        if obj.get("system") == "http://unitsofmeasure.org" \
                and isinstance(obj.get("code"), str) \
                and "{" in obj["code"]:
            obj["code"] = re.sub(r'\s*\{[^}]*\}', '', obj["code"]).strip()

        # Fix: UCUM code starting with # (double hash like ##/100 WBC)
        if obj.get("system") == "http://unitsofmeasure.org" \
                and isinstance(obj.get("code"), str) \
                and obj["code"].startswith("#"):
            obj["code"] = obj["code"].lstrip("#").strip()

        # Fix: unknown UCUM units - replace with DAR
        UNKNOWN_UCUM = {"mOsmol/kg", "mOsmol", "mosm/kg", "mosm/L",
                        "mosm", "eq/L", "meq/L"}
        if obj.get("system") == "http://unitsofmeasure.org" \
                and obj.get("code") in UNKNOWN_UCUM:
            obj["system"] = DAR
            obj["code"] = "unknown"
            obj.pop("display", None)

        # Fix: Remove ALL LOINC and SNOMED display names
        # HAPI validates displays against the CodeSystem and often rejects them
        if obj.get("system") in ("http://loinc.org", "http://snomed.info/sct") \
                and "display" in obj:
            del obj["display"]

        # Fix: date obviously wrong (year > 2100)
        for field in ("birthDate", "date", "effectiveDateTime",
                      "performedDateTime", "recordedDate", "onsetDateTime",
                      "abatementDateTime", "authoredOn", "start", "end",
                      "deceasedDateTime", "lastUpdated", "timestamp"):
            if field in obj and isinstance(obj.get(field), str):
                m = re.match(r'^(\d{4})', obj[field])
                if m and int(m.group(1)) > 2100:
                    obj[field] = obj[field].replace(m.group(1), "2024", 1)

        # Fix: Identifier.system not absolute URI
        if "system" in obj and "value" in obj and                 isinstance(obj.get("system"), str) and                 not obj["system"].startswith(("http", "urn:", "oid:",
                    "phone", "email", "fax", "url", "sms", "pager", "other")):
            obj["system"] = "urn:local:" + obj["system"]

        # Fix: answerOption valueCoding with no system
        # LA... codes are LOINC answer list codes
        if "code" in obj and "system" not in obj and                 isinstance(obj.get("code"), str) and                 "resourceType" not in obj and                 "value" not in obj:
            code = obj["code"]
            if code.startswith("LA") and len(code) > 4:
                obj["system"] = "http://loinc.org"
            elif code in ("Yes", "No", "Unknown", "UNK"):
                obj["system"] = "http://terminology.hl7.org/CodeSystem/v2-0532"

        # Fix: trailing/leading whitespace in string fields
        for field in ("text", "name", "title", "description", "linkId",
                      "prefix", "definition"):
            if field in obj and isinstance(obj.get(field), str) \
                    and (obj[field] != obj[field].strip()):
                obj[field] = obj[field].strip()

        # Fix: null issued / null extension
        if "issued" in obj and obj["issued"] is None:
            del obj["issued"]
        if "extension" in obj and obj["extension"] is None:
            del obj["extension"]

        # Fix: empty arrays in known fields
        for key in list(obj.keys()):
            if key in EMPTY_ARRAY_FIELDS \
                    and isinstance(obj[key], list) \
                    and len(obj[key]) == 0:
                del obj[key]

        # Fix: empty objects {}
        for key in list(obj.keys()):
            if isinstance(obj[key], dict) and len(obj[key]) == 0:
                obj[key] = {"coding": [{"system": DAR,
                                         "code": "unknown",
                                         "display": "Unknown"}]}

        for v in list(obj.values()):
            fix_object(v)

    elif isinstance(obj, list):
        for item in obj:
            fix_object(item)


def fix_resource(resource):
    """Resource-type-specific fixes."""
    rt = resource.get("resourceType")

    # dom-6: add narrative if missing (handle text=None explicitly)
    text = resource.get("text")
    if not isinstance(text, dict) or not text.get("div"):
        resource["text"] = {"status": "generated", "div": NARRATIVE}

    # Account.coverage.coverage required
    if rt == "Account":
        for cov in resource.get("coverage", []):
            if isinstance(cov, dict) and not cov.get("coverage"):
                cov["coverage"] = {"display": "Unknown Coverage"}

    # Claim required fields
    if rt == "Claim":
        if not resource.get("created"):
            resource["created"] = "1970-01-01T00:00:00Z"
        # addItem.adjudication required
        for add_item in resource.get("addItem", []):
            if isinstance(add_item, dict) and not add_item.get("adjudication"):
                add_item["adjudication"] = [{
                    "category": {"coding": [{"system":
                        "http://terminology.hl7.org/CodeSystem/adjudication",
                        "code": "benefit", "display": "Benefit Amount"}]},
                    "amount": {"value": 0, "currency": "USD"}
                }]
        if not resource.get("priority"):
            resource["priority"] = {"coding": [{"system":
                "http://terminology.hl7.org/CodeSystem/processpriority",
                "code": "normal"}]}
        for ins in resource.get("insurance", []):
            if isinstance(ins, dict) and ins.get("focal") is None:
                ins["focal"] = True
        for proc in resource.get("procedure", []):
            if isinstance(proc, dict) \
                    and not proc.get("procedureCodeableConcept") \
                    and not proc.get("procedureReference"):
                proc["procedureCodeableConcept"] = {
                    "coding": [{"system": DAR, "code": "unknown"}]}

    # ClaimResponse required fields
    if rt == "ClaimResponse":
        if not resource.get("patient"):
            resource["patient"] = {"display": "Unknown Patient"}
        if not resource.get("insurer"):
            resource["insurer"] = {"display": "Unknown Insurer"}
        if not resource.get("created"):
            resource["created"] = "1970-01-01T00:00:00Z"
        # addItem.adjudication required
        for add_item in resource.get("addItem", []):
            if isinstance(add_item, dict) and not add_item.get("adjudication"):
                add_item["adjudication"] = [{
                    "category": {"coding": [{"system":
                        "http://terminology.hl7.org/CodeSystem/adjudication",
                        "code": "benefit", "display": "Benefit Amount"}]},
                    "amount": {"value": 0, "currency": "USD"}
                }]

    # Consent.scope required
    if rt == "Consent":
        if not resource.get("scope"):
            resource["scope"] = {"coding": [{
                "system": "http://terminology.hl7.org/CodeSystem/consentscope",
                "code": "patient-privacy",
                "display": "Privacy Consent"}]}
        # Fix Consent.category - consentscope codes are not valid here
        # category must use consent-category ValueSet
        cats = resource.get("category", [])
        if isinstance(cats, list):
            for cat in cats:
                if isinstance(cat, dict):
                    codings = cat.get("coding", [])
                    if isinstance(codings, list):
                        for coding in codings:
                            if isinstance(coding, dict) and                                coding.get("system") ==                                "http://terminology.hl7.org/CodeSystem/consentscope":
                                coding["system"] =                                     "http://terminology.hl7.org/CodeSystem/consentcategorycodes"
                                coding["code"] = "59284-0"
                                coding.pop("display", None)

    # ExplanationOfBenefit required fields
    if rt == "ExplanationOfBenefit":
        if not resource.get("insurer"):
            resource["insurer"] = {"display": "Unknown Insurer"}
        resource.pop("priority", None)  # processpriority CS vs VS HAPI bug
        for ins in resource.get("insurance", []):
            if isinstance(ins, dict) and ins.get("focal") is None:
                ins["focal"] = True

    # Family Planning invalid type in Encounter
    if rt == "Encounter":
        if isinstance(resource.get("class"), dict) and            resource["class"].get("display") == "Family Planning":
            resource["class"] = {
                "system": "http://terminology.hl7.org/CodeSystem/v3-ActCode",
                "code": "AMB", "display": "ambulatory"
            }
        if isinstance(resource.get("subject"), dict) and            resource["subject"].get("type") == "Family Planning":
            del resource["subject"]["type"]

    # MedicationRequest.intent required
    if rt == "MedicationRequest":
        if not resource.get("intent"):
            resource["intent"] = "order"

    # PaymentNotice.recipient required
    if rt == "PaymentNotice":
        if not resource.get("recipient"):
            resource["recipient"] = {"display": "Unknown Recipient"}

    # PaymentReconciliation required fields
    if rt == "PaymentReconciliation":
        if not resource.get("status"):
            resource["status"] = "active"
        if not resource.get("paymentDate"):
            resource["paymentDate"] = "1970-01-01"

    # Remove unknown extensions
    BAD_EXT_PREFIXES = (
        "http://mihin.org",
        "https://mihin.org",
        "http://fhir-registry.smarthealthit.org",
        "https://fhir-registry.smarthealthit.org",
    )
    exts = resource.get("extension")
    if isinstance(exts, list):
        resource["extension"] = [
            e for e in exts
            if not (isinstance(e, dict) and
                    any(e.get("url", "").startswith(p) for p in BAD_EXT_PREFIXES))
        ]
        if not resource["extension"]:
            del resource["extension"]

    # Remove meta.profile to prevent SNOMED ValueSet expansion failures
    meta = resource.get("meta", {})
    if isinstance(meta.get("profile"), list):
        del meta["profile"]
    # Remove meta.tag entries with no system (e.g. lformsVersion tags)
    if isinstance(meta.get("tag"), list):
        meta["tag"] = [t for t in meta["tag"]
                       if isinstance(t, dict) and t.get("system")]
        if not meta["tag"]:
            del meta["tag"]


def main():
    if len(sys.argv) < 3:
        print(f"Usage: python3 {sys.argv[0]} input.json output.json")
        sys.exit(1)

    input_file  = sys.argv[1]
    output_file = sys.argv[2]
    fhir_base   = os.environ.get("FHIR_BASE", FHIR_BASE)

    print(f"Reading  : {input_file}")
    with open(input_file) as f:
        bundle = json.load(f)

    entry_count = len(bundle.get("entry", []))
    print(f"Entries  : {entry_count}")
    print(f"FHIR base: {fhir_base}")

    data = copy.deepcopy(bundle)
    fu_added = 0

    print("Applying fixes...")
    for entry in data.get("entry", []):
        resource = entry.get("resource", {})
        if not resource:
            continue
        # Add fullUrl if missing
        if "fullUrl" not in entry \
                and resource.get("id") \
                and resource.get("resourceType"):
            entry["fullUrl"] = \
                f"{fhir_base}/{resource['resourceType']}/{resource['id']}"
            fu_added += 1
        fix_resource(resource)

    fix_object(data)

    final_count = len(data.get("entry", []))
    if final_count != entry_count:
        print(f"WARNING: Entry count changed {entry_count} -> {final_count}")
    else:
        print(f"Entry count OK : {final_count}")
    print(f"fullUrl added  : {fu_added}")

    # Final cleanup: ensure ALL LOINC and SNOMED codings have no display
    def remove_loinc_snomed_displays(obj):
        if isinstance(obj, dict):
            if obj.get("system") in ("http://loinc.org", "http://snomed.info/sct") \
                    and "display" in obj:
                del obj["display"]
            for v in list(obj.values()):
                remove_loinc_snomed_displays(v)
        elif isinstance(obj, list):
            for item in obj:
                remove_loinc_snomed_displays(item)

    remove_loinc_snomed_displays(data)

    print(f"Writing  : {output_file}")
    with open(output_file, "w") as f:
        json.dump(data, f)
    print("Done.")


if __name__ == "__main__":
    main()
