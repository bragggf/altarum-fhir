Now I have the complete picture. Let me apply all fixes:All checks pass, 813 entries preserved. Here is a summary of the 17 fixes applied:

| # | Issue | Count | Fix |
|---|---|---|---|
| 1 | **Missing `fullUrl`** on all entries | 813 | Added absolute `http://localhost:4004/hapi-fhir-jpaserver/fhir/ResourceType/id` |
| 2 | **Claim required R4 fields** missing | 17 each | Added `created`, `priority`, `insurance.focal`, `procedure.procedure[x]` |
| 3 | **`MedicationRequest.intent`** missing | 2 | Defaulted to `"order"` |
| 4 | **`Account.coverage.coverage`** missing | 1 | Added `{"display":"Unknown"}` |
| 5 | **`Family Planning`** invalid resource type in `Encounter.class` and `subject.type` | 2 | `class` replaced with valid v3-ActCode `AMB`; `subject.type` removed |
| 6 | **`null` literal codes** in modifier/diagnosis CodeSystems | 30+ | Replaced with `data-absent-reason#unknown` |
| 7 | **DL wrong display name** — `"Driver's License"` | 457 | Removed display, let server use canonical |
| 8 | **LOINC/SNOMED wrong display names** | 351 | Removed all display names for these systems |
| 9 | **`J1100 `** trailing space in code | 1 | Trimmed to `"J1100"` |
| 10 | **Date-only `issued`** instead of instant | 2 | Appended `T00:00:00Z` |
| 11 | **`Posiive`** typo | 1 | Corrected to `"Positive"` |
| 12 | **`JMC system`** non-absolute identifier system | 1 | Prefixed as `urn:local:JMC-system` |
| 13 | **`us-core-race/ethnicity`** wrong value type | 2 | Converted `valueCodeableConcept` to `ombCategory`/`text` sub-extensions |
| 14 | **`us-core-2`** Observation with no value | 1 | Added `dataAbsentReason#unknown` |
| 15 | **`Specimen.type`** missing | 1 | Added `data-absent-reason#unknown` |
| 16 | **Unverifiable profiles** (cancer-reporting, SDC, SDOH) | 95 | Removed profile declarations not installed on server |
| 17 | **Missing narrative** (`dom-6`) | 161 | Added minimal generated `text.div` |

```bash
./load_fhir_bundle-fixed.sh test-data-helios-fixed.json \
  http://localhost:4004/hapi-fhir-jpaserver/fhir 2>&1 | tee sof_helios_test_2.out
```
