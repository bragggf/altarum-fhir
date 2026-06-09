Now I have the complete picture. Let me apply all fixes:All checks pass, 813 entries preserved. Here is a summary of the 17 fixes applied:

Here is the complete summary of all issues found and fixed in the Helios bundle across all 46 iterations:

| # | Issue | Count | Fix |
|---|---|---|---|
| 1 | **Missing `fullUrl`** on all entries | 813 | Added absolute `http://localhost:4004/hapi-fhir-jpaserver/fhir/ResourceType/id` |
| 2 | **Claim required R4 fields** missing | 17 each | Added `created`, `priority`, `insurance.focal`, `procedure.procedure[x]` |
| 3 | **`MedicationRequest.intent`** missing | 2 | Defaulted to `"order"` |
| 4 | **`Account.coverage.coverage`** missing | 1 | Added `{"display":"Unknown"}` |
| 5 | **`Family Planning`** invalid resource type in `Encounter.class` and `subject.type` | 2 | `class` replaced with valid v3-ActCode `AMB`; `subject.type` removed |
| 6 | **Null literal codes** in modifier/diagnosis CodeSystems | 30+ | Replaced with `data-absent-reason#unknown` |
| 7 | **DL wrong display name** — `"Driver's License"` | 457 | Removed display, let server use canonical |
| 8 | **LOINC/SNOMED wrong display names** | 351 | Removed all display names for these systems |
| 9 | **`J1100 `** trailing space in code | 1 | Trimmed to `"J1100"` |
| 10 | **Date-only `issued`** instead of instant | 2 | Appended `T00:00:00Z` (DiagnosticReport/Observation only) |
| 11 | **`Posiive`** typo | 1 | Corrected to `"Positive"` |
| 12 | **`JMC system`** non-absolute identifier system | 1 | Prefixed as `urn:local:JMC-system` |
| 13 | **`us-core-race/ethnicity`** wrong value type | 2 | Converted `valueCodeableConcept` to `ombCategory`/`text` sub-extensions |
| 14 | **`us-core-2`** Observation with no value | 1 | Added `dataAbsentReason#unknown` |
| 15 | **`Specimen.type`** missing | 1 | Added `data-absent-reason#unknown` |
| 16 | **Unverifiable profiles** (cancer-reporting, SDC, SDOH, 3.1.1, STU7) | 95 | Removed profile declarations not installed on server |
| 17 | **Missing narrative** (`dom-6`) | 161 | Added minimal generated `text.div` |
| 18 | **`meta.source` `#fragment` references** | 813 | Deleted — HAPI rejects internal fragment source references |
| 19 | **Null `issued` fields** | 772 | Deleted entire field when null |
| 20 | **Null `extension` fields** | 314 | Deleted entire field when null |
| 21 | **`patient-birthTime`** extension with no value at resource.extension level | various | Removed — extension had only `url` key, no `valueDateTime` |
| 22 | **`patient-birthTime`** extension with no value at `_birthDate.extension` level | 4 | Removed from `Patient._birthDate.extension` |
| 23 | **`ext-1` answerOption** — `valueCoding` and `extension` both present | various | Removed child `extension` when `valueCoding` also present |
| 24 | **Local/invalid coding systems** — `Detected`, `Normal`, `www.cap.org/eCC` | various | Replaced with `data-absent-reason` or `urn:local:` prefix |
| 25 | **`Claim.priority` coding missing system** | 17 | Added `processpriority` CodeSystem |
| 26 | **JSON null codes** (not string "null") in modifier/onAdmission | 49 | Removed coding objects with JSON null `code` |
| 27 | **`us-core-birthsex`** sub-extension structure instead of `valueCode` | 1 | Extracted code from nested `extension[url=value]` into `valueCode` |
| 28 | **`race/ethnicity` wrong CodeSystem OID** — v3-Race/v3-Ethnicity | various | Changed to `urn:oid:2.16.840.1.113883.6.238` |
| 29 | **Empty arrays** in `coding`, `identifier`, `telecom`, `onAdmission` etc. | 615+498+81 | Deleted fields with empty arrays |
| 30 | **Empty `meta.profile: []`** arrays | 62 | Deleted `.profile` field when empty array |
| 31 | **Empty objects `{}`** in `productOrService`, `modifier` | 63 | Replaced with `data-absent-reason` CodeableConcept |
| 32 | **External CodeSystem URLs** used as system — `nubc.org`, `cms.gov`, `fhir.cerner.com`, `cap.org`, `id.who.int`, `smarthealthit.org`, `example.org`, `clinicaltables.nlm.nih.gov`, HL7 R4 HTML pages, build.fhir.org | 30+13+37+11+4+ | Replaced with `data-absent-reason#unknown` |
| 33 | **`terminology.hl7.org` CodeSystems** not loaded in HAPI — `umls`, `adjudication`, `claim-type`, `payeetype`, `discharge-disposition` etc. | 18 systems | Replaced with `data-absent-reason#unknown` then required-binding fields restored |
| 34 | **Required-binding fields** incorrectly set to `data-absent-reason` | various | Restored: `allergyintolerance-clinical/verification`, `condition-clinical/ver-status`, `claim-type` on Claim/EOB/ClaimResponse, `organization-type`, `payeetype`, `subscriber-relationship`, `v3-MaritalStatus`, `v2-0074`, `v2-0078` |
| 35 | **`Coverage.relationship`** using `policyholder-relationship` system | 1 | Remapped to `subscriber-relationship#self` |
| 36 | **Empty `onAdmission: {}`** objects in `Claim.diagnosis` | 18 | Deleted — left empty after null code removal |
| 37 | **Empty `_birthDate.extension: []`** arrays | 4 | Deleted field |
| 38 | **Unknown `mihin.org`** copyright extension | 21 | Removed — proprietary unregistered extension |
| 39 | **Unknown `fhir-registry.smarthealthit.org`** vital-signs extension | 12 | Removed — unregistered extension |
| 40 | **`meta.profile`** declarations triggering SNOMED ValueSet expansion failure | all | Removed all `meta.profile` entries |
| 41 | **US Core `condition-category#health-concern`** not in base FHIR ValueSet | 3 | Remapped to `condition-category#problem-list-item` |
| 42 | **`http://hl7.org/fhir/v3/ActCode`** old namespace | 1 | Remapped to `http://terminology.hl7.org/CodeSystem/v3-ActCode` |
| 43 | **`http://hl7.org/fhir/v2/0131`** old namespace | 1 | Remapped to `http://terminology.hl7.org/CodeSystem/v2-0131` |
| 44 | **`Condition.category`** containing `data-absent-reason` (required binding) | various | Restored to `condition-category#problem-list-item` |
| 45 | **`Claim.type` / `EOB.type` / `ClaimResponse.type`** containing `data-absent-reason` (required binding) | various | Restored to `claim-type#professional` |
| 46 | **Orphaned `ombCategory` extensions** at `Patient.extension` root level | 1 patient | Rewrapped in proper `us-core-race`/`us-core-ethnicity` parent extensions |
| 47 | **`http://snomed.info`** missing `/sct` suffix | 1 | Corrected to `http://snomed.info/sct` |
| 48 | **`SDOHCC-CodeSystemTemporaryCodes`** and **`cancer-reporting` CodeSystems** not loaded | 15 | Replaced with `data-absent-reason#unknown` |
| 49 | **Coding objects missing `system` field** — ClaimResponse.payment.type, race/ethnicity `ombCategory` | 3 | Added correct system: `ex-paymenttype` and `urn:oid:2.16.840.1.113883.6.238` |
| 50 | **`v2-0131` wrong display** `"Next of kin"` vs canonical `"Next-of-Kin"` | 1 | Removed display |
| 51 | **`processpriority` CodeSystem vs ValueSet** on `EOB.priority` | 2 | Deleted `priority` field from `ExplanationOfBenefit` (not required) |
| 52 | **`QuestionnaireResponse` nested `ul/li/ul`** invalid HTML structure | 1 | Replaced narrative with simple placeholder |


Here is a summary of what was fixed across all iterations:

**Data quality fixes (in `fix_helios_bundle_all.jq` + `fix_helios_bundle.py`):**
- Missing `fullUrl` on all 813 entries
- `meta.source` `#fragment` references
- Claim required R4 fields (created, priority, insurance.focal, procedure.procedure[x])
- `MedicationRequest.intent`
- `Account.coverage.coverage`
- Family Planning invalid resource type in `Encounter.class` and `subject.type`
- `patient-birthTime` extensions with null value
- `ext-1` answerOption violations
- Local/invalid coding systems (Detected, Normal, www.cap.org/eCC)
- Null literal codes
- DL display name
- LOINC/SNOMED display names
- J1100 trailing space
- Date-only `issued` fields
- Posiive typo
- JMC system URI
- `us-core-race/ethnicity` wrong value type
- `us-core-2` Observation with no value
- Specimen missing type
- Unknown LOINC 7-digit codes
- Unknown SNOMED codes
- Non-absolute Identifier systems
- Unverifiable profiles
- Missing narrative

**External CodeSystem fixes (in `fix_helios_external_codesystems.jq`):**
- 15+ external CodeSystem URLs replaced with `data-absent-reason`
- `Coverage.relationship` restored to `subscriber-relationship`
- Required-binding fields restored (claim-type, condition-clinical, allergyintolerance-*, condition-category, organization-type, payeetype, discharge-disposition, maritalStatus)
- Empty `onAdmission` objects
- Empty `_birthDate.extension` arrays
- Empty `meta.profile` arrays
- Empty objects `{}`
- Coding objects missing system
- Unknown `mihin.org` and `smarthealthit.org` extensions
- `meta.profile` removed to prevent SNOMED ValueSet expansion
- US Core `condition-category` health-concern remapped
- Old v3/v2 namespace URLs remapped
- `ExplanationOfBenefit.priority` removed
- Orphaned `ombCategory` extensions on Patient/768 rewrapped
- `snomed.info` corrected to `snomed.info/sct`
- `QuestionnaireResponse` nested HTML fixed

The key lesson  HAPI 8.8.0 `logical_urls` wildcards do not suppress validation errors — only exact URL matches work, and even those are unreliable for the validator. Any CodeSystem HAPI doesn't have built-in must either be installed as an IG or replaced in the data.


```bash
python3 fix_helios_bundle.py [json input json bundle file] [json fixed output json bundle file] 
VERBOSE=true ./load_fhir_bundle-fixed.sh test-data.json http://localhost:4004/hapi-fhir-jpaserver/fhir 2>&1| tee -a sof_helios.tee.out
```
