#!/usr/bin/env python3
"""
check_chunks.py
Scans all split bundle chunks and classifies them as:
  - SKIP: contains only FHIR conformance resources (StructureDefinition, etc.)
  - LOAD: contains clinical data resources
  - MIXED: contains both conformance and clinical resources

Usage:
    python3 check_chunks.py ./chunks/
    python3 check_chunks.py ./chunks/ --skip-list skip_chunks.txt
    python3 check_chunks.py ./chunks/ --move-skip ./conformance_chunks/
    python3 check_chunks.py ./chunks/ --delete-skip
    ./check_chunks.py ./chunks/ -v [verbose]

Output:
    Prints classification for each chunk and a summary.
    Optionally writes a skip list file for use with the load script.
"""

import os
import sys
import json
import glob
import shutil
import argparse
from collections import Counter


CONFORMANCE_TYPES = {
    "StructureDefinition",
    "SearchParameter",
    "ValueSet",
    "CodeSystem",
    "NamingSystem",
    "OperationDefinition",
    "CapabilityStatement",
    "CompartmentDefinition",
    "ImplementationGuide",
    "GraphDefinition",
    "MessageDefinition",
    "ExampleScenario",
    "TestScript",
    "TestReport",
    "TerminologyCapabilities",
}


def classify_chunk(filepath):
    """
    Returns:
        (classification, resource_types, entry_count)
        classification: "SKIP" | "LOAD" | "MIXED" | "EMPTY" | "ERROR"
    """
    try:
        with open(filepath) as f:
            bundle = json.load(f)
    except json.JSONDecodeError as e:
        return "ERROR", {}, 0, str(e)
    except Exception as e:
        return "ERROR", {}, 0, str(e)

    entries = bundle.get("entry", [])
    if not entries:
        return "EMPTY", set(), 0, ""

    resource_types = Counter()
    for entry in entries:
        rt = entry.get("resource", {}).get("resourceType", "Unknown")
        resource_types[rt] += 1

    all_types = set(resource_types.keys())
    conformance = all_types & CONFORMANCE_TYPES
    clinical = all_types - CONFORMANCE_TYPES

    if all_types <= CONFORMANCE_TYPES:
        classification = "SKIP"
    elif conformance and clinical:
        classification = "MIXED"
    else:
        classification = "LOAD"

    return classification, resource_types, len(entries), ""


def main():
    parser = argparse.ArgumentParser(description="Classify FHIR bundle chunks")
    parser.add_argument("chunk_dir", help="Directory containing chunk JSON files")
    parser.add_argument("--pattern", default="chunk_*.json",
                        help="Glob pattern for chunk files (default: chunk_*.json)")
    parser.add_argument("--skip-list", metavar="FILE",
                        help="Write list of SKIP chunk filenames to this file")
    parser.add_argument("--load-list", metavar="FILE",
                        help="Write list of LOAD chunk filenames to this file")
    parser.add_argument("--move-skip", metavar="DIR",
                        help="Move SKIP chunks to this directory")
    parser.add_argument("--delete-skip", action="store_true",
                        help="Delete SKIP chunks")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Show resource type breakdown for each chunk")
    args = parser.parse_args()

    # Find all chunk files
    pattern = os.path.join(args.chunk_dir, args.pattern)
    chunk_files = sorted(glob.glob(pattern))

    if not chunk_files:
        print(f"No files found matching: {pattern}")
        sys.exit(1)

    print(f"Found {len(chunk_files)} chunk files in {args.chunk_dir}")
    print()

    # Create move directory if needed
    if args.move_skip:
        os.makedirs(args.move_skip, exist_ok=True)

    # Classify each chunk
    results = {
        "SKIP": [],
        "LOAD": [],
        "MIXED": [],
        "EMPTY": [],
        "ERROR": [],
    }

    total_entries = 0
    total_conformance_entries = 0
    total_clinical_entries = 0

    for filepath in chunk_files:
        filename = os.path.basename(filepath)
        classification, resource_types, entry_count, error_msg = classify_chunk(filepath)

        results[classification].append(filepath)
        total_entries += entry_count

        # Count entries by category
        conf_entries = sum(v for k, v in resource_types.items()
                          if k in CONFORMANCE_TYPES)
        clin_entries = sum(v for k, v in resource_types.items()
                          if k not in CONFORMANCE_TYPES)
        total_conformance_entries += conf_entries
        total_clinical_entries += clin_entries

        # Print classification
        icon = {"SKIP": "⊘", "LOAD": "✓", "MIXED": "~",
                "EMPTY": "∅", "ERROR": "✗"}.get(classification, "?")
        print(f"  {icon} {classification:5s}  {filename}  ({entry_count} entries)")

        if error_msg:
            print(f"         Error: {error_msg}")

        if args.verbose and resource_types:
            for rt, count in sorted(resource_types.items(), key=lambda x: -x[1]):
                marker = "  [conformance]" if rt in CONFORMANCE_TYPES else "  [clinical]  "
                print(f"           {count:4d}  {rt}{marker}")

        # Move or delete if requested
        if classification == "SKIP":
            if args.move_skip:
                dest = os.path.join(args.move_skip, filename)
                shutil.move(filepath, dest)
                print(f"         → moved to {dest}")
            elif args.delete_skip:
                os.remove(filepath)
                print(f"         → deleted")

    # Summary
    print()
    print("=== SUMMARY ===")
    print(f"  Total chunks : {len(chunk_files)}")
    print(f"  LOAD         : {len(results['LOAD'])}  (clinical data — load these)")
    print(f"  SKIP         : {len(results['SKIP'])}  (conformance only — skip these)")
    print(f"  MIXED        : {len(results['MIXED'])}  (both — load but may have issues)")
    print(f"  EMPTY        : {len(results['EMPTY'])}  (no entries)")
    print(f"  ERROR        : {len(results['ERROR'])}  (parse errors)")
    print()
    print(f"  Total entries          : {total_entries}")
    print(f"  Clinical entries       : {total_clinical_entries}")
    print(f"  Conformance entries    : {total_conformance_entries}")

    # Write skip list
    if args.skip_list:
        with open(args.skip_list, "w") as f:
            for filepath in results["SKIP"]:
                f.write(filepath + "\n")
        print(f"\n  Skip list written to: {args.skip_list}")

    # Write load list
    if args.load_list:
        load_files = results["LOAD"] + results["MIXED"]
        with open(args.load_list, "w") as f:
            for filepath in sorted(load_files):
                f.write(filepath + "\n")
        print(f"  Load list written to: {args.load_list}")

    # Print MIXED chunks detail
    if results["MIXED"]:
        print(f"\n  MIXED chunks (review these):")
        for fp in results["MIXED"]:
            print(f"    {os.path.basename(fp)}")

    print()
    return len(results["ERROR"]) > 0


if __name__ == "__main__":
    sys.exit(0 if not main() else 1)
