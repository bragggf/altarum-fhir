#!/usr/bin/env python3
"""
split-bundle.py
Splits a large FHIR bundle into smaller batch chunks for loading.

Usage:
    python3 split-bundle.py input.json output_dir/ [chunk_size]
    
Example:
    python3 chunk_bundle.py large-bundle.json ./chunks/ 200
"""

import sys
import json
import os
import math

def chunk_bundle(input_file, output_dir, chunk_size=200):
    print(f"Reading {input_file}...")
    
    with open(input_file) as f:
        bundle = json.load(f)
    
    entries = bundle.get("entry", [])
    total = len(entries)
    num_chunks = math.ceil(total / chunk_size)
    
    print(f"Total entries : {total}")
    print(f"Chunk size    : {chunk_size}")
    print(f"Total chunks  : {num_chunks}")
    
    # Build template without entries - preserve all bundle metadata
    template = {k: v for k, v in bundle.items() if k != "entry"}
    template["type"] = "batch"  # force batch type
    
    os.makedirs(output_dir, exist_ok=True)
    
    # Convert transaction PUT/POST entries to batch-compatible entries
    for entry in entries:
        if "request" not in entry:
            # Add a default request if missing
            resource = entry.get("resource", {})
            rt = resource.get("resourceType", "Resource")
            rid = resource.get("id")
            if rid:
                entry["request"] = {"method": "PUT", "url": f"{rt}/{rid}"}
            else:
                entry["request"] = {"method": "POST", "url": rt}
    
    chunk_files = []
    for i in range(num_chunks):
        start = i * chunk_size
        end = min(start + chunk_size, total)
        chunk_entries = entries[start:end]
        
        chunk = dict(template)
        chunk["entry"] = chunk_entries
        
        filename = os.path.join(output_dir, f"chunk_{i+1:04d}_of_{num_chunks:04d}.json")
        with open(filename, "w") as f:
            json.dump(chunk, f)
        
        size_mb = os.path.getsize(filename) / (1024 * 1024)
        print(f"  chunk {i+1:4d}/{num_chunks}: entries {start+1}-{end} ({size_mb:.1f} MB) -> {filename}")
        chunk_files.append(filename)
    
    print(f"\nDone. {num_chunks} chunks written to {output_dir}")
    return chunk_files


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: python3 {sys.argv[0]} input.json output_dir/ [chunk_size]")
        sys.exit(1)
    
    input_file  = sys.argv[1]
    output_dir  = sys.argv[2]
    chunk_size  = int(sys.argv[3]) if len(sys.argv) > 3 else 200
    
    chunk_bundle(input_file, output_dir, chunk_size)
