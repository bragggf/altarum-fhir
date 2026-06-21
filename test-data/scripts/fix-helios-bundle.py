#!/usr/bin/env python3
"""
fix_helios_bundle.py
Complete single-step fix pipeline for Helios FHIR R4 batch bundle.
Applies all 52 fixes documented in the session summary.

Usage:
    python3 fix_helios_bundle.py input.json output.json
    FHIR_BASE=http://localhost:4004/hapi-fhir-jpaserver/fhir \
        python3 fix_helios_bundle.py input.json output.json

Requires: jq installed on PATH, python3

Pipeline:
    Step 1 - jq: fix_helios_bundle_all.jq    (33 data quality fixes)
    Step 2 - py: fix_birthsex()               (us-core-birthsex sub-extension)
    Step 3 - py: fix_orphaned_race_ext()      (Patient orphaned ombCategory)
    Step 4 - py: fix_nested_extensions()      (remove mihin/smarthealthit extensions)
    Step 5 - jq: fix_helios_external_codesystems.jq  (18 CodeSystem fixes)
"""

import sys
import json
import subprocess
import copy
import os

FHIR_BASE = "http://localhost:4004/hapi-fhir-jpaserver/fhir"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def run_jq(script_file, data):
    """Run a jq script file against data dict, return result dict."""
    proc = subprocess.run(
        ["jq", "-f", script_file],
        input=json.dumps(data).encode(),
        capture_output=True
    )
    if proc.returncode != 0:
        raise RuntimeError(f"jq error in {script_file}:\n{proc.stderr.decode()}")
    return json.loads(proc.stdout)


def run_jq_expr(expr, data):
    """Run a jq expression string against data dict, return result dict."""
    proc = subprocess.run(
        ["jq", expr],
        input=json.dumps(data).encode(),
        capture_output=True
    )
    if proc.returncode != 0:
        raise RuntimeError(f"jq error:\n{proc.stderr.decode()}")
    return json.loads(proc.stdout)


def fix_birthsex(data):
    """
    Fix us-core-birthsex sub-extension structure -> valueCode.
    jq cannot safely handle null valueCode with nested valueCodeableConcept.
    """
    data = copy.deepcopy(data)
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


def fix_orphaned_race_ext(data):
    """
    Fix Patient resources where ombCategory sub-extensions ended up at
    the root extension level without a parent us-core-race/ethnicity wrapper.
    """
    data = copy.deepcopy(data)
    for entry in data.get("entry", []):
        resource = entry.get("resource", {})
        if resource.get("resourceType") != "Patient":
            continue
        extensions = resource.get("extension", [])
        if not isinstance(extensions, list):
            continue

        orphaned = [e for e in extensions if isinstance(e, dict) and e.get("url") == "ombCategory"]
        if not orphaned:
            continue

        proper = [e for e in extensions if not (isinstance(e, dict) and e.get("url") in ("ombCategory", "text", "detailed"))]
        race_codings = [e for e in orphaned if not (e.get("valueCoding", {}).get("code", "").startswith("2135"))]
        eth_codings  = [e for e in orphaned if e.get("valueCoding", {}).get("code", "").startswith("2135")]

        new_exts = proper[:]
        if race_codings:
            new_exts.append({
                "url": "http://hl7.org/fhir/us/core/StructureDefinition/us-core-race",
                "extension": race_codings + [{"url": "text", "valueString": "White"}]
            })
        if eth_codings:
            new_exts.append({
                "url": "http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity",
                "extension": eth_codings + [{"url": "text", "valueString": "Hispanic or Latino"}]
            })
        resource["extension"] = new_exts
    return data


def fix_nested_extensions(data):
    """
    Remove mihin.org and smarthealthit.org extensions at any nesting level.
    Uses Python walk to avoid jq dropping .entry[] items.
    """
    BAD_PREFIXES = (
        "http://mihin.org",
        "https://mihin.org",
        "http://fhir-registry.smarthealthit.org",
    )

    def remove_bad(obj):
        if isinstance(obj, dict):
            if "extension" in obj and isinstance(obj["extension"], list):
                obj["extension"] = [
                    e for e in obj["extension"]
                    if not (isinstance(e, dict) and
                            any(e.get("url", "").startswith(p) for p in BAD_PREFIXES))
                ]
                if len(obj["extension"]) == 0:
                    del obj["extension"]
            for k, v in list(obj.items()):
                if k != "extension":
                    remove_bad(v)
        elif isinstance(obj, list):
            for item in obj:
                remove_bad(item)

    data = copy.deepcopy(data)
    for entry in data.get("entry", []):
        remove_bad(entry.get("resource", {}))
    return data


def main():
    if len(sys.argv) < 3:
        print(f"Usage: python3 {sys.argv[0]} input.json output.json")
        sys.exit(1)

    input_file  = sys.argv[1]
    output_file = sys.argv[2]
    fhir_base   = os.environ.get("FHIR_BASE", FHIR_BASE)

    print(f"Reading   : {input_file}")
    with open(input_file) as f:
        bundle = json.load(f)

    entry_count = len(bundle.get("entry", []))
    print(f"Entries   : {entry_count}")

    # Patch FHIR_BASE into jq script 1
    jq1_path = os.path.join(SCRIPT_DIR, "fix_helios_bundle_all.jq")
    with open(jq1_path) as f:
        jq1 = f.read().replace(
            "http://localhost:4004/hapi-fhir-jpaserver/fhir/",
            fhir_base.rstrip("/") + "/"
        )

    print("Step 1/5 : jq data quality fixes...")
    proc = subprocess.run(
        ["jq", "-c", jq1],
        input=json.dumps(bundle).encode(),
        capture_output=True
    )
    if proc.returncode != 0:
        print(f"jq error: {proc.stderr.decode()}")
        sys.exit(1)
    bundle = json.loads(proc.stdout)
    print(f"           {len(bundle.get('entry', []))} entries after step 1")

    print("Step 2/5 : birthsex sub-extension fix...")
    bundle = fix_birthsex(bundle)

    print("Step 3/5 : orphaned race/ethnicity extension fix...")
    bundle = fix_orphaned_race_ext(bundle)

    print("Step 4/5 : nested extension removal (mihin/smarthealthit)...")
    bundle = fix_nested_extensions(bundle)

    print("Step 5/5 : external CodeSystem fixes...")
    jq2_path = os.path.join(SCRIPT_DIR, "fix_helios_external_codesystems.jq")
    proc = subprocess.run(
        ["jq", "-f", jq2_path],
        input=json.dumps(bundle).encode(),
        capture_output=True
    )
    if proc.returncode != 0:
        print(f"jq error: {proc.stderr.decode()}")
        sys.exit(1)
    bundle = json.loads(proc.stdout)

    final_count = len(bundle.get("entry", []))
    if final_count != entry_count:
        print(f"WARNING: Entry count changed {entry_count} -> {final_count}")
    else:
        print(f"Entries OK: {final_count}")

    print(f"Writing   : {output_file}")
    with open(output_file, "w") as f:
        json.dump(bundle, f)
    print("Done.")


if __name__ == "__main__":
    main()
