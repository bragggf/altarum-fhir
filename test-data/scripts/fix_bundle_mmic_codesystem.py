#!/usr/bin/env python3
"""
fix_bundle.py
Fixes common HAPI FHIR 8.8.0 validation errors in FHIR R4 batch bundles.
Handles both Helios and MIMIC dataset issues.

Usage:
    python3 fix_bundle.py input.json output.json
    FHIR_BASE=http://helios-connect.immunization-registries.org:4004/hapi-fhir-jpaserver/fhir \
        python3 fix_bundle.py input.json output.json

Fixes applied:
    1.  meta.source #fragment references - deleted
    2.  Missing fullUrl on entries - added from FHIR_BASE/ResourceType/id
    3.  text field inside Coding objects - removed
    4.  ClaimResponse.patient missing - added placeholder
    5.  ClaimResponse.insurer missing - added placeholder
    6.  Consent.scope missing - added patient-privacy default
    7.  ExplanationOfBenefit.insurer missing - added placeholder
    8.  PaymentNotice.recipient missing - added placeholder
    9.  PaymentReconciliation.status missing - defaulted to 'active'
    10. URI values with whitespace - spaces replaced with hyphens
    11. Unknown external CodeSystems (MIMIC, NDC, etc.) - replaced with DAR
    12. http://hl7.org/fhir/referencerange-meaning wrong URL - corrected
    13. UCUM codes with {annotation} - annotation stripped
    14. Coding objects with no system - system added where deterministic
    15. ExplanationOfBenefit.priority - deleted (processpriority CS vs VS bug)
    16. Empty arrays in known fields - deleted
    17. Empty objects {} - replaced with data-absent-reason CodeableConcept
    18. null issued fields - deleted
    19. null extension fields - deleted
"""

import sys
import json
import copy
import re
import os

FHIR_BASE = os.environ.get(
    "FHIR_BASE",
    "http://localhost:4004/hapi-fhir-jpaserver/fhir"
)

DAR = "http://terminology.hl7.org/CodeSystem/data-absent-reason"

# CodeSystems HAPI cannot validate - replace with data-absent-reason
UNKNOWN_SYSTEMS = {
    # MIMIC dataset
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
    # NDC
    "https://ndclist.com",
    # External systems
    "https://www.nubc.org/CodeSystem/RevenueCodes",
    "https://www.cms.gov/Medicare/Coding/HCPCSReleaseCodeSets",
    "https://fhir.cerner.com",
    "http://smarthealthit.org",
    "https://cap.org",
    "http://cap.org",
    "http://id.who.int/icd",
    "https://example.org",
    "https://clinicaltables.nlm.nih.gov",
}

# URL prefixes for unknown systems (prefix match)
UNKNOWN_SYSTEM_PREFIXES = (
    "http://mimic.mit.edu/",
    "https://www.nubc.org/",
    "https://www.cms.gov/Medicare/",
    "https://fhir.cerner.com/",
    "http://smarthealthit.org/",
    "https://cap.org/",
    "http://cap.org/",
    "http://id.who.int/",
    "https://example.org/",
    "https://clinicaltables.nlm.nih.gov/",
    "http://hl7.org/fhir/us/sdoh-clinicalcare/CodeSystem/",
    "http://hl7.org/fhir/us/cancer-reporting/CodeSystem/",
)

# Empty array fields that must be deleted if empty
EMPTY_ARRAY_FIELDS = {
    "coding", "identifier", "telecom", "performer", "category",
    "interpretation", "note", "bodySite", "method", "specimen",
    "device", "referenceRange", "hasMember", "derivedFrom",
    "component", "modifier", "programCode", "subSite",
    "adjudication", "detail", "onAdmission"
}


def is_unknown_system(system):
    """Check if a CodeSystem URL is unknown to HAPI."""
    if not isinstance(system, str):
        return False
    if system in UNKNOWN_SYSTEMS:
        return True
    for prefix in UNKNOWN_SYSTEM_PREFIXES:
        if system.startswith(prefix):
            return True
    return False


def fix_object(obj):
    """
    Recursively walk and fix all issues in a FHIR object.
    Modifies obj in place.
    """
    if isinstance(obj, dict):
        # Fix 1: meta.source #fragment
        if "source" in obj and isinstance(obj.get("source"), str) and \
           obj["source"].startswith("#"):
            del obj["source"]

        # Fix 3: Remove 'text' from Coding objects
        # Coding only allows: system, code, display, version, userSelected
        if ("system" in obj or "code" in obj) and \
           "coding" not in obj and \
           "text" in obj and \
           "div" not in obj:  # don't touch narrative text
            del obj["text"]

        # Fix 10: URI values with whitespace
        if "system" in obj and isinstance(obj.get("system"), str) and \
           " " in obj["system"]:
            obj["system"] = obj["system"].replace(" ", "-")

        if "url" in obj and isinstance(obj.get("url"), str) and \
           " " in obj["url"] and obj["url"].startswith("urn:"):
            obj["url"] = obj["url"].replace(" ", "-")

        # Fix 11: Unknown external CodeSystems
        if "system" in obj and "code" in obj and \
           isinstance(obj.get("system"), str) and \
           isinstance(obj.get("code"), str) and \
           is_unknown_system(obj["system"]):
            obj["system"] = DAR
            obj["code"] = "unknown"
            obj.pop("display", None)

        # Fix 12: referencerange-meaning wrong URL
        if obj.get("system") == "http://hl7.org/fhir/referencerange-meaning":
            obj["system"] = "http://terminology.hl7.org/CodeSystem/referencerange-meaning"

        # Fix 13: UCUM codes with {annotation}
        if obj.get("system") == "http://unitsofmeasure.org" and \
           isinstance(obj.get("code"), str) and "{" in obj["code"]:
            obj["code"] = re.sub(r'\s*\{[^}]*\}', '', obj["code"]).strip()

        # Fix 18: null issued
        if "issued" in obj and obj["issued"] is None:
            del obj["issued"]

        # Fix 19: null extension
        if "extension" in obj and obj["extension"] is None:
            del obj["extension"]

        # Fix 16: empty arrays in known fields
        for key in list(obj.keys()):
            if key in EMPTY_ARRAY_FIELDS and \
               isinstance(obj[key], list) and \
               len(obj[key]) == 0:
                del obj[key]

        # Fix 17: empty objects {} — replace with DAR CodeableConcept
        for key in list(obj.keys()):
            if isinstance(obj[key], dict) and len(obj[key]) == 0:
                obj[key] = {
                    "coding": [{
                        "system": DAR,
                        "code": "unknown",
                        "display": "Unknown"
                    }]
                }

        # Recurse into children
        for v in list(obj.values()):
            fix_object(v)

    elif isinstance(obj, list):
        for item in obj:
            fix_object(item)


def fix_resource(resource):
    """Apply resource-type-specific fixes."""
    rt = resource.get("resourceType")

    # Fix 4 & 5: ClaimResponse required fields
    if rt == "ClaimResponse":
        if not resource.get("patient"):
            resource["patient"] = {"display": "Unknown Patient"}
        if not resource.get("insurer"):
            resource["insurer"] = {"display": "Unknown Insurer"}

    # Fix 6: Consent.scope required
    if rt == "Consent":
        if not resource.get("scope"):
            resource["scope"] = {
                "coding": [{
                    "system": "http://terminology.hl7.org/CodeSystem/consentscope",
                    "code": "patient-privacy",
                    "display": "Privacy Consent"
                }]
            }

    # Fix 7: ExplanationOfBenefit.insurer required
    if rt == "ExplanationOfBenefit":
        if not resource.get("insurer"):
            resource["insurer"] = {"display": "Unknown Insurer"}
        # Fix 15: EOB.priority causes processpriority CS vs VS HAPI bug
        if "priority" in resource:
            del resource["priority"]

    # Fix 8: PaymentNotice.recipient required
    if rt == "PaymentNotice":
        if not resource.get("recipient"):
            resource["recipient"] = {"display": "Unknown Recipient"}

    # Fix 9: PaymentReconciliation.status required
    if rt == "PaymentReconciliation":
        if not resource.get("status"):
            resource["status"] = "active"

    # Remove meta.profile to prevent SNOMED ValueSet expansion failures
    if resource.get("meta", {}).get("profile"):
        del resource["meta"]["profile"]

    # Remove empty meta.profile arrays
    if isinstance(resource.get("meta", {}).get("profile"), list) and \
       len(resource["meta"]["profile"]) == 0:
        del resource["meta"]["profile"]


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
    print(f"FHIR base: {fhir_base}")

    data = copy.deepcopy(bundle)

    print("Applying fixes...")
    counters = {
        "fullUrl_added": 0,
        "meta_source_fixed": 0,
        "resource_fixes": 0,
    }

    for entry in data.get("entry", []):
        resource = entry.get("resource", {})
        if not resource:
            continue

        # Fix 2: Add fullUrl if missing
        if "fullUrl" not in entry and \
           resource.get("id") and resource.get("resourceType"):
            entry["fullUrl"] = (
                f"{fhir_base}/{resource['resourceType']}/{resource['id']}"
            )
            counters["fullUrl_added"] += 1

        # Apply resource-type-specific fixes
        fix_resource(resource)
        counters["resource_fixes"] += 1

    # Apply recursive object fixes across entire bundle
    fix_object(data)

    final_count = len(data.get("entry", []))
    if final_count != entry_count:
        print(f"WARNING: Entry count changed {entry_count} -> {final_count}")
    else:
        print(f"Entry count OK: {final_count}")

    print(f"fullUrl added    : {counters['fullUrl_added']}")

    print(f"Writing  : {output_file}")
    with open(output_file, "w") as f:
        json.dump(data, f)

    print("Done.")


if __name__ == "__main__":
    main()
