# Integrating HAPI FHIR 8.x into smart-dev-sandbox

This guide documents how to replace the default `smartonfhir/hapi-5` R4 server
in `smart-dev-sandbox` with a current `hapiproject/hapi` 8.x server while
maintaining full compatibility with the SMART Launcher, Patient Browser, and
FHIR Viewer.

## Background

The `smart-dev-sandbox` project ships with `smartonfhir/hapi-5` images — custom
Tomcat-based HAPI FHIR servers that predate HAPI's migration to Spring Boot.
Replacing them with the current `hapiproject/hapi` image requires bridging
several architectural differences:

| | `smartonfhir/hapi-5` | `hapiproject/hapi` 8.x |
|---|---|---|
| Runtime | Tomcat / Catalina | Spring Boot (embedded Tomcat) |
| Startup | `catalina.sh run` | Java WAR auto-launch |
| Config | `hapi.properties` template | `application.yaml` |
| Default port | 8080 | 8080 (configurable) |
| Context path | `/hapi-fhir-jpaserver` | `/` (configurable) |
| Database path | `/usr/local/tomcat/target/database` | `/app/database` |

The `smart-dev-sandbox` launcher and other services expect the R4 FHIR endpoint
at `http://<host>:<R4_PORT>/hapi-fhir-jpaserver/fhir`. Since `hapiproject/hapi`
serves at `/fhir` by default and generates self-referencing URLs based on its
own context path, an nginx reverse proxy is used to handle the translation
transparently.

---

## Architecture

```
Browser / SMART Launcher
        │
        ▼
 nginx-r4 (port R4_PORT)          ← context path translation
   /hapi-fhir-jpaserver/* ──────► hapi-r4:4004/
   /fhir/*                ──────► hapi-r4:4004/fhir/
        │
        ▼ (r4net bridge network)
 hapi-r4 (port 4004, internal only)
   hapiproject/hapi:v8.8.0-1
```

Both `nginx-r4` and `hapi-r4` share a dedicated bridge network (`r4net`).
The `smart-launcher` is also added to `r4net` so it can resolve `nginx-r4`
by container name for server-to-server FHIR calls.

---

## Prerequisites

- Docker and Docker Compose
- A clone of [smart-on-fhir/smart-dev-sandbox](https://github.com/smart-on-fhir/smart-dev-sandbox)
- The `R4_PORT` value from your `.env` file (default `9004`)

---

## Step 1 — Create the nginx configuration

Create the directory and config file:

```bash
mkdir -p nginx
```

Create `nginx/r4.conf` — replace `9004` with your actual `R4_PORT` if different:

```nginx
server {
    listen 9004;

    # Translate /hapi-fhir-jpaserver/* to HAPI's native /fhir/* path
    location /hapi-fhir-jpaserver/ {
        proxy_pass         http://hapi-r4:4004/;
        proxy_set_header   Host              $host:4004;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_redirect     http://hapi-r4:4004/ http://$host:$server_port/hapi-fhir-jpaserver/;
    }

    # HAPI UI self-links use /fhir/ directly — pass through unchanged
    location /fhir/ {
        proxy_pass         http://hapi-r4:4004/fhir/;
        proxy_set_header   Host              $host:4004;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_redirect     http://hapi-r4:4004/ http://$host:$server_port/;
    }

    # Root and everything else
    location / {
        proxy_pass         http://hapi-r4:4004/;
        proxy_set_header   Host              $host:4004;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_redirect     http://hapi-r4:4004/ http://$host:$server_port/;
    }
}
```

> **Note on `Host: $host:4004`:** HAPI uses the `Host` header to construct
> self-referencing URLs in the CapabilityStatement and pagination links. The
> port must be included so HAPI generates correct URLs rather than defaulting
> to port 80.

---

## Step 2 — Create the HAPI configuration

Create the config and database directories:

```bash
mkdir -p r4-config r4-database
```

Create `r4-config/application.yaml` with a minimal configuration:

```yaml
server:
  port: 4004

hapi:
  fhir:
    fhir_version: R4
    client_id_strategy: ANY
    enforce_referential_integrity_on_write: false
    enforce_referential_integrity_on_delete: false
    validation:
      requests_enabled: false
    implementationguides:
      us_core_610:
        name: hl7.fhir.us.core
        version: 6.1.0
        reloadExisting: false
        installMode: STORE_AND_INSTALL
    # Route LOINC/SNOMED validation to HL7 public terminology server
    # (required since these CodeSystems are not bundled with HAPI)
    remote_terminology_service:
      all:
        system: "*"
        url: "https://tx.fhir.org/r4/"
    # Disable pre-expansion to prevent stale expansion errors
    pre_expand_value_sets: false
    enable_task_pre_expand_value_sets: false
```

For advanced configuration including additional Implementation Guides,
logical_urls for external CodeSystems, and bundle loading settings see the
[HAPI FHIR JPA Server documentation](https://hapifhir.io/hapi-fhir/docs/server_jpa/get_started.html).

---

## Step 3 — Update `docker-compose.yml`

Add a top-level `networks` section and replace the `r4` service with two
new services — `r4-internal` (HAPI) and `nginx-r4` (reverse proxy).
Also add `smart-launcher` to `r4net` so server-to-server FHIR calls resolve
correctly.

### Add to the top-level `networks` section

```yaml
networks:
  r4net:
    driver: bridge
```

### Replace the `r4` service with

```yaml
  nginx-r4: # ------------------------------------------------------------------
    container_name: nginx-r4
    image: nginx:alpine
    ports:
      - "0.0.0.0:${R4_PORT}:${R4_PORT}"
    volumes:
      - "./nginx/r4.conf:/etc/nginx/conf.d/default.conf:ro"
    networks:
      - r4net
    depends_on:
      - r4-internal
    deploy:
      replicas: ${R4_ENABLED}

  r4-internal: # ---------------------------------------------------------------
    container_name: hapi-r4
    image: hapiproject/hapi:v8.8.0-1
    environment:
      - PORT=${R4_PORT}
      - HOST=${HOST}
      - "SPRING_CONFIG_LOCATION=file:/app/config/application.yaml"
      - JAVA_TOOL_OPTIONS=-Xms512m -Xmx4g
    volumes:
      - type: bind
        source: ./r4-config
        target: /app/config
      - type: bind
        source: ./r4-database
        target: /app/database
    networks:
      - r4net
    # NOTE: No command: override — hapiproject/hapi uses Spring Boot,
    # not Tomcat/Catalina. The original smartonfhir/hapi-5 command block
    # (envsubst + catalina.sh) must NOT be used with this image.
    deploy:
      resources:
        limits:
          cpus: "${R4_CPU_CORES}"
          memory: ${R4_MEMORY}
      replicas: ${R4_ENABLED}
```

### Update the `smart-launcher` service

Add `r4net` to networks and update the R4 internal URL:

```yaml
  smart-launcher:
    # ... existing config ...
    environment:
      # ... existing vars ...
      # External URL unchanged — nginx handles context path translation
      - FHIR_SERVER_R4=http://${HOST}:${R4_PORT}/hapi-fhir-jpaserver/fhir
      # Internal URL routes through nginx-r4 (resolved via r4net)
      - FHIR_SERVER_R4_INTERNAL=http://nginx-r4:${R4_PORT}/hapi-fhir-jpaserver/fhir
    networks:
      - r4net
```

---

## Step 4 — Update `.env`

Set the R4 image to the HAPI 8.x release:

```bash
R4_IMAGE=hapiproject/hapi:v8.8.0-1
```

> **Warning:** When switching images, delete the existing R4 database volume
> first to prevent H2 schema conflicts:
> ```bash
> docker volume rm smart-dev-sandbox_r4-database
> # or if using bind mount:
> rm -rf ./r4-database/*
> ```

---

## Step 5 — Start and verify

```bash
docker compose down
docker compose up -d

# HAPI takes ~90 seconds to start and install US Core packages
# Watch progress:
docker logs hapi-r4 --follow | grep -i "started\|installing\|error"

# Once Started Application appears, test both paths:
curl -s http://localhost:9004/fhir/metadata | head -3
curl -s http://localhost:9004/hapi-fhir-jpaserver/fhir/metadata | head -3
```

Both should return a FHIR R4 CapabilityStatement.

---

## Troubleshooting

### Empty response from curl despite port mapping looking correct

Check what port HAPI is actually listening on inside the container:

```bash
CONTAINER_IP=$(docker inspect hapi-r4 --format \
  '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
curl -s http://${CONTAINER_IP}:4004/fhir/metadata | head -3
```

If this works but `localhost:R4_PORT` doesn't, the Docker port mapping target
is wrong. Ensure the container-side port in `docker-compose.yml` matches the
`server.port` in `application.yaml`.

### nginx cannot resolve `hapi-r4`

Both `nginx-r4` and `r4-internal` must be on the same Docker network (`r4net`).
Verify with:

```bash
docker network inspect smart-dev-sandbox_r4net | grep -A5 "Containers"
```

Both containers should appear in the output.

### HAPI generates URLs without port number

Ensure the nginx config sets `proxy_set_header Host $host:4004` (with the
explicit port) in every `location` block. Without the port, HAPI constructs
self-referencing URLs that omit the port number and become unreachable.

### US Core package install fails on startup

The HAPI container needs outbound internet access to `packages.fhir.org` and
`tx.fhir.org`. Verify connectivity from inside the container:

```bash
docker exec hapi-r4 wget -qO- https://tx.fhir.org/r4/metadata | head -3
```

### OOM / Java heap space errors on large bundle loads

Increase the heap allocation in the `r4-internal` environment:

```yaml
- JAVA_TOOL_OPTIONS=-Xms512m -Xmx6g
```

Or split the bundle into smaller chunks before loading.

---

## Key differences from `smartonfhir/hapi-5`

1. **No `command:` override** — `hapiproject/hapi` launches via Spring Boot.
   Including the `catalina.sh` command from the original config will crash
   the container immediately.

2. **Config via `application.yaml`** — all settings go in `application.yaml`
   mounted at `/app/config/`. The `hapi.properties` template system used by
   `smartonfhir/hapi-5` does not apply.

3. **Database path** — H2 database files live at `/app/database`, not
   `/usr/local/tomcat/target/database`.

4. **Port is set in `application.yaml`** — `server.port: 4004` controls the
   internal port. The `PORT` environment variable has no effect on
   `hapiproject/hapi`.

5. **Context path** — `hapiproject/hapi` serves at `/fhir` by default.
   The nginx proxy provides the `/hapi-fhir-jpaserver/fhir` path that the
   SMART Launcher expects without requiring HAPI to be reconfigured.
