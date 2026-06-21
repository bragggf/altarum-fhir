#!/bin/bash

# Skip chunks that contain only conformance resources
python3 - << 'EOF'
import json, sys

SKIP_TYPES = {"StructureDefinition", "SearchParameter", "ValueSet", 
              "CodeSystem", "NamingSystem", "OperationDefinition",
              "CapabilityStatement", "CompartmentDefinition"}

with open("chunk_0001_of_0133.json") as f:
    bundle = json.load(f)

resource_types = {e.get("resource",{}).get("resourceType") 
                  for e in bundle.get("entry",[])}

if resource_types <= SKIP_TYPES:
    print(f"SKIP - conformance resources only: {resource_types}")
else:
    print(f"LOAD - contains clinical data: {resource_types - SKIP_TYPES}")
EOF
