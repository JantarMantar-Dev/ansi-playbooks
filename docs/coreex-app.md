# CoreEx Application Operations

This document holds CoreEx-specific deployment notes. General remote Docker and Dokploy operations live in [../remote-docker-env.md](../remote-docker-env.md).

## Service

CoreEx is deployed by Dokploy as a Docker Swarm service.

```text
service: coreex-app-70cz87
image: zot.jbaba.dev/zotuser/coreex-app-70cz87:latest
runtime port: 3000
network: dokploy-network / gp32g4stpvymb9ol3yb02paln
public apex: https://coreex.in/
wildcard subdomains: https://<tenant>.coreex.in/
```

After the 2026-07-09 recovery the service is temporarily allowed to run on the manager because worker nodes were unavailable. Before that recovery it had a `node.role==worker` placement constraint.

Check service state:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159
sudo docker service ps --no-trunc coreex-app-70cz87
sudo docker service logs --tail 100 coreex-app-70cz87
sudo docker service inspect coreex-app-70cz87 --pretty
```

Check the live container:

```bash
cid=$(sudo docker ps --filter name=coreex-app-70cz87 --format "{{.ID}}" | head -n1)
sudo docker exec "$cid" sh -lc 'ps aux; netstat -ltnp || true; wget -S -O- -T 10 http://127.0.0.1:3000/ || true'
```

Expected healthy output includes Vite listening on `0.0.0.0:3000` and a `200 OK` local request.

## Public Verification

```bash
curl -k -L --max-time 25 -I https://coreex.in/
curl -k -L --max-time 25 https://coreex.in/ | head
curl -k -L --max-time 25 -I https://test.coreex.in/
```

Expected behavior:

* `https://coreex.in/` returns `200`.
* An unknown tenant subdomain, such as `https://test.coreex.in/`, returns the app-rendered tenant-not-found page, currently with HTTP `404`.

## Historical Image Startup Failure

Previous failure:

```text
task: non-zero exit (1)
vite.config.ts:5:30: ERROR: Could not resolve "./src/server/api/auth-api"
```

Root cause:

The production Docker runtime stage did not copy `./src` and `./tsconfig.json` from the build stage. `pnpm run start:prod` runs `vite preview`, and Vite loads `vite.config.ts`; without `./src`, esbuild failed while loading config imports.

Fix used in the CoreEx app Dockerfile:

```dockerfile
COPY --from=build /app/src ./src
COPY --from=build /app/tsconfig.json ./tsconfig.json
```

## Wildcard Subdomain Routing

CoreEx needs wildcard tenant routing for subdomains like:

```text
https://abc.coreex.in/
https://test.coreex.in/
```

Dokploy's standard wildcard domain entry generated an invalid Traefik TLS rule:

```text
Host(`*.coreex.in`)
error while adding rule HostSNI(`*.coreex.in`): invalid value for HostSNI matcher
```

Because Cloudflare terminates SSL/TLS at the edge, the manager uses a custom Traefik dynamic config file instead:

```text
/etc/dokploy/traefik/dynamic/coreex-wildcard.yml
```

Config:

```yaml
http:
  routers:
    coreex-app-wildcard-router:
      rule: HostRegexp(`^[a-z0-9-]+\.coreex\.in$`)
      service: coreex-app-wildcard-service
      entryPoints:
        - websecure
      tls: {}
    coreex-app-wildcard-router-http:
      rule: HostRegexp(`^[a-z0-9-]+\.coreex\.in$`)
      service: coreex-app-wildcard-service
      middlewares:
        - redirect-to-https
      entryPoints:
        - web
  services:
    coreex-app-wildcard-service:
      loadBalancer:
        servers:
          - url: http://coreex-app-70cz87:3000
        passHostHeader: true
```

Why this is safe:

* Dokploy manages service-specific dynamic files, not unrelated custom files like `coreex-wildcard.yml`.
* `HostRegexp` is valid in Traefik v3.
* The config routes by HTTP host header and avoids invalid wildcard SNI matching.

Verify the file:

```bash
sudo sed -n '1,120p' /etc/dokploy/traefik/dynamic/coreex-wildcard.yml
sudo docker logs --tail 100 dokploy-traefik 2>&1 | grep -i coreex
```

## Dokploy UI Cleanup

To prevent Dokploy from regenerating a conflicting wildcard rule:

1. Open `https://dokploy.jbaba.dev/`.
2. Go to the CoreEx application.
3. Open Domains.
4. Keep `coreex.in`.
5. Remove any standard UI domain entry for `*.coreex.in`.

## Debug Helper

Use the repo-local helper:

```bash
./scripts/infra/debug-ssh-manager.sh coreex-app
```

The helper checks SSH, swarm nodes, service replicas, tasks, logs, and service image metadata.
