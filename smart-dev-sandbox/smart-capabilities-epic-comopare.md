Here is a side-by-side comparison and what changes are needed:

---

## Comparison

| Field | Your sandbox | Epic |
|---|---|---|
| `authorization_endpoint` | `http://192.168.6.193:4013/v/r4/auth/authorize` | `https://fhir.epic.com/.../oauth2/authorize` |
| `token_endpoint` | `http://192.168.6.193:4013/v/r4/auth/token` | `https://fhir.epic.com/.../oauth2/token` |
| `introspection_endpoint` | `http://192.168.6.193:4013/v/r4/auth/introspect` | *(not declared)* |
| `issuer` | *(missing)* | `https://fhir.epic.com/.../oauth2` |
| `jwks_uri` | *(missing)* | declared (asymmetric key endpoint) |
| `token_endpoint_auth_methods_supported` | `client_secret_basic`, `client_secret_post` | adds `private_key_jwt` |
| `grant_types_supported` | *(missing)* | `authorization_code`, `refresh_token`, `client_credentials`, `jwt-bearer`, `token-exchange` |
| `code_challenge_methods_supported` | *(missing)* | `S256` |
| `response_types_supported` | `code` | `code` ✓ |

### Capabilities comparison

| Capability | Your sandbox | Epic |
|---|---|---|
| `launch-ehr` | ✓ | ✓ |
| `launch-standalone` | ✓ | ✓ |
| `client-public` | ✓ | ✓ |
| `client-confidential-symmetric` | ✓ | ✓ |
| `client-confidential-asymmetric` | **missing** | ✓ |
| `context-banner` | `context-passthrough-banner` (renamed) | `context-banner` |
| `context-style` | `context-passthrough-style` (renamed) | `context-style` |
| `context-ehr-patient` | ✓ | ✓ |
| `context-ehr-encounter` | ✓ | ✓ |
| `context-standalone-patient` | ✓ | ✓ |
| `context-standalone-encounter` | ✓ | **missing** in Epic |
| `permission-offline` | ✓ | ✓ |
| `permission-patient` | ✓ | ✓ |
| `permission-user` | ✓ | ✓ |
| `permission-v1` | **missing** | ✓ |
| `permission-v2` | **missing** | ✓ |
| `sso-openid-connect` | **missing** | ✓ |
| `authorize-post` | **missing** | ✓ |

### Scopes comparison

| Scope | Your sandbox | Epic |
|---|---|---|
| `openid` | ✓ | ✓ |
| `profile` | ✓ | ✓ |
| `fhirUser` | ✓ | ✓ |
| `launch` | ✓ | ✓ |
| `launch/patient` | ✓ | **not declared** |
| `launch/encounter` | ✓ | **not declared** |
| `patient/*.*` | ✓ | **not declared** (implied) |
| `user/*.*` | ✓ | **not declared** (implied) |
| `offline_access` | ✓ | **not declared** |
| `epic.scanning.dmsusername` | **missing** | ✓ (Epic proprietary) |

---

## Configuration changes needed

The `smart-dev-sandbox` launcher generates this discovery document dynamically — it cannot be edited directly via a config file. The changes require either modifying the launcher source or accepting the differences. Here is what is realistic to change:

**1. Add `code_challenge_methods_supported` — high priority**

The SMART App Launch v2 spec requires PKCE. The launcher supports S256 but doesn't declare it. This is the most important gap for connectathon interoperability. Add to the launcher environment in `docker-compose.yml`:

```yaml
smart-launcher:
  environment:
    - PKCE_ENABLED=1
```

Check the launcher docs — some versions support `PKCE_ENABLED` or `CODE_CHALLENGE_METHODS`.

**2. Add `issuer` — required for SMART v2**

The launcher needs a base URL configured:

```yaml
smart-launcher:
  environment:
    - BASE_URL=http://192.168.6.193:4013
    - LAUNCHER_BASE_URL=http://192.168.6.193:4013
```

This should cause the launcher to populate the `issuer` field.

**3. Add `grant_types_supported`** — the launcher currently supports `authorization_code` and `refresh_token` but doesn't declare them. This is a declaration-only gap, not a functional one.

**4. Add `private_key_jwt` to `token_endpoint_auth_methods_supported`** — Epic uses asymmetric JWT authentication for backend services (`client_credentials` with `private_key_jwt`). The `smart-dev-sandbox` launcher does not support backend services authentication at all. This is an architectural limitation — not configurable.

**5. Capability name corrections** — `context-passthrough-banner` and `context-passthrough-style` are older names. The current SMART spec uses `context-banner` and `context-style`. These are declared in the launcher source and would require a code change to rename.

**6. `permission-v1` and `permission-v2`** — these are Epic-specific SMART scope versioning capabilities, not standard SMART spec. Not applicable to `smart-dev-sandbox`.

**7. `authorize-post`** — Epic supports POST to the authorization endpoint. Not supported in `smart-dev-sandbox`.

**Summary of achievable vs not achievable:**

| Change | Achievable in smart-dev-sandbox |
|---|---|
| `code_challenge_methods_supported: S256` | Likely via env var |
| `issuer` field | Yes via `BASE_URL` env var |
| `grant_types_supported` declaration | Would require source code change |
| `private_key_jwt` auth method | No — not implemented |
| `client-confidential-asymmetric` capability | No — not implemented |
| `sso-openid-connect` capability | Partially — launcher does OpenID Connect |
| `context-banner`/`context-style` names | Source code change only |
| `permission-v1`/`permission-v2` | Not applicable |
| `authorize-post` | Not implemented |

