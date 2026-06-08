
Here is a summary of the 10 issues fixed in the OPHDST bundle:

| # | Issue | Root Cause | Fix |
|---|---|---|---|
| 1 | **Missing `fullUrl`** on all 41 entries | Bundle generated without fullUrl — causes all relative reference errors | Added absolute URL `http://localhost:4004/hapi-fhir-jpaserver/fhir/ResourceType/id` to every entry |
| 2 | **`encounter-diagnosis` wrong CodeSystem** | Used `http://hl7.org/fhir/us/core/CodeSystem/condition-category` (US Core proprietary) instead of the standard HL7 system | Changed system to `http://terminology.hl7.org/CodeSystem/condition-category` |
| 3 | **`per-1` constraint violation** | A Period had `start` date later than `end` date | Swapped start and end values |
| 4 | **`Posiive` typo** | Misspelled display name on an ObservationInterpretation coding | Corrected to `Positive` |
| 5 | **`birthsex` trailing space** | `valueCode` was `"F "` with a trailing space — fails ValueSet validation | Trimmed to `"F"` |
| 6 | **`Specimen.type` missing** | Required field (`1..1`) in FHIR R4 was absent | Added `data-absent-reason#unknown` as default type |
| 7 | **`us-core-2` Observation with no value** | Observation had no `value[x]`, no `dataAbsentReason`, no `component`, and no `hasMember` — violates US Core constraint | Added `dataAbsentReason#unknown` |
| 8 | **Wrong display name for SNOMED `266919005`** | Display was `"Never smoker"` — SNOMED canonical is `"Never smoked"` | Corrected to `"Never smoked"` |
| 9 | **US Core 3.1.1 and STU7 profile references** | `meta.profile` contained versioned US Core 3.1.1 URLs and an STU7 draft URL — neither installed on the server | Removed the 16 versioned 3.1.1 profiles and 1 STU7 profile reference |
| 10 | **Missing narrative** (`dom-6`) | Resources had no `text.div` — best-practice constraint enforced by `RequestValidatingInterceptor` | Added minimal generated narrative to all affected resources |

Issues 1 and 9 account for the bulk of the 83 errors (72 of them). The remaining 8 issues were one error each — typical of data quality problems in source system exports rather than systematic generation errors.


