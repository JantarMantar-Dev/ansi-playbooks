# Remote Docker Environment

This is the top-level operations document for the shared remote Docker/Dokploy environment. Keep this file focused on general infrastructure, service availability, and production recovery basics. App-specific notes belong in separate docs, such as [docs/coreex-app.md](docs/coreex-app.md).

## Purpose

The environment hosts several production applications behind Dokploy and Traefik. Dokploy manages application services, dynamic Traefik route files, private registry deployment metadata, and service updates. Docker Swarm provides service scheduling.

Primary operator goals:

1. Keep Dokploy, Traefik, registry access, and database-bearing services available.
2. Restore public application routes quickly during worker or network incidents.
3. Avoid destructive actions against production volumes, databases, secrets, and swarm config.
4. Document every recovery action that changes service placement, replicas, or routing.

## Access

Manager node:

```text
racknerd-fb2892c
public IP: 107.175.69.159
user: jbaba
ssh key: ~/.ssh/ssdnode-2025
```

Preferred SSH command when the local SSH host alias is stale:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159
```

Inventory:

```bash
prod-docker/setup-swarm/inventory.ini
```

Ansible reachability check:

```bash
ansible -i prod-docker/setup-swarm/inventory.ini all -m ping
```

## Core Components

| Component | Service/container | Purpose | Data sensitivity |
| :--- | :--- | :--- | :--- |
| Dokploy | `dokploy` | Deployment UI/control plane | High |
| Dokploy Postgres | `dokploy-postgres` | Dokploy database | High |
| Dokploy Redis | `dokploy-redis` | Dokploy cache/queue state | Medium |
| Traefik | `dokploy-traefik` | Public HTTP/HTTPS routing | Medium |
| Zot registry | `infra-zot-xlzvhg-zot-1` | Private image registry | High |
| ViralReel DB | `viralreel-db-vwkfbt` | ViralReel production Postgres | High |
| OpenObserve/Vector | `openobserve`, `infra-openobserve-qfmox1_vector` | Logs/observability | Medium |

Critical volumes:

```text
dokploy
dokploy-postgres
dokploy-redis
viralreel-db-vwkfbt-data
infra-maillayer-lkymqv-data
```

Never remove these volumes during incident response.

## Public Applications

Routes are generated under `/etc/dokploy/traefik/dynamic/*.yml` on the manager.

Current important services and public routes:

| Service | Expected replicas after 2026-07-09 recovery | Public route |
| :--- | :--- | :--- |
| `buildinpublic-app-b37nff` | `1/1` | `https://buildinpublic.page/` |
| `coreex-app-70cz87` | `1/1` | `https://coreex.in/` |
| `jbaba-blog-hq29mq` | `1/1` | `https://blog.jbaba.dev/` |
| `serivcehq-web-wpqe73` | `1/1` | `https://servicehq.biz/` |
| `viralreel-appapi-rad4ao` | `2/2` | `https://api.getviralreel.com/` |
| `viralreel-appclient-vopczf` | `2/2` | `https://app.getviralreel.com/` |
| `viralreel-lending-erhdij` | `2/2` | `https://getviralreel.com/` |
| `dokploy` | `1/1` | `https://dokploy.jbaba.dev/` |

Some services intentionally remain scaled to zero:

```text
cogniva-frontend-5rir6o
games-mathfactory-u6notk
viralreel-appworker-xu6rte
```

Do not scale them up during a general outage unless the app owner asks for it.

## Baseline Health Checks

Run from the manager:

```bash
sudo docker node ls
sudo docker service ls
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
sudo docker volume ls
```

Inspect dynamic routes:

```bash
sudo find /etc/dokploy/traefik/dynamic -maxdepth 1 -type f -name "*.yml" -print
sudo grep -R "Host(" /etc/dokploy/traefik/dynamic
sudo grep -R "url:" /etc/dokploy/traefik/dynamic
```

Check service tasks and logs:

```bash
sudo docker service ps --no-trunc <service-name>
sudo docker service logs --tail 100 <service-name>
```

Check a container from inside:

```bash
cid=$(sudo docker ps --filter name=<service-name> --format "{{.ID}}" | head -n1)
sudo docker exec "$cid" sh -lc 'ps aux; netstat -ltnp || true; wget -S -O- -T 10 http://127.0.0.1:3000/ || true'
```

Use the repo helper:

```bash
./scripts/infra/debug-ssh-manager.sh
./scripts/infra/debug-ssh-manager.sh coreex-app
./scripts/infra/debug-ssh-manager.sh viralreel
```

## Public Availability Check

Run from the local machine:

```bash
urls=(
  "https://coreex.in/"
  "https://test.coreex.in/"
  "https://buildinpublic.page/"
  "https://www.buildinpublic.page/"
  "https://blog.jbaba.dev/"
  "https://servicehq.biz/"
  "https://www.servicehq.biz/"
  "https://getviralreel.com/"
  "https://www.getviralreel.com/"
  "https://app.getviralreel.com/"
  "https://api.getviralreel.com/"
  "https://dokploy.jbaba.dev/"
)

for u in "${urls[@]}"; do
  printf "%-38s " "$u"
  curl -k -L --max-time 25 -s -o /dev/null \
    -w "code=%{http_code} bytes=%{size_download} time=%{time_total}\n" "$u"
done
```

Expected notes:

* `https://api.getviralreel.com/` can return `404` for `GET /`; that still proves the API is reachable.
* `https://test.coreex.in/` should return the CoreEx app-rendered tenant-not-found page, currently as HTTP `404`.
* `https://www.buildinpublic.page/` returned `403` on 2026-07-09 due to app-level host allowlist behavior while the apex route worked.

## Production Safety Rules

Do not run these during emergency recovery unless there is a clear backup/restore plan and explicit approval:

```bash
docker system prune --volumes
docker volume rm ...
docker swarm leave --force   # on the manager
docker swarm init            # on the manager
ansible-playbook ... update-swarm.yml -e "force_leader_reinit=true"
```

High-risk commands:

* `docker system prune -a --volumes` can delete production volumes.
* `docker node rm` can remove swarm membership records. Use only after confirming the node is intentionally gone.
* Manager `docker swarm leave --force` destroys the currently active swarm manager state.
* Reinitializing the leader creates new swarm state and can lose service/config/secret definitions.

Safe first moves:

1. Inspect service state.
2. Preserve database services and volumes.
3. Pre-pull images instead of repeatedly forcing service updates.
4. Prefer temporary placement changes over swarm reinitialization.
5. Verify with curl before and after each repair phase.

## Incident Runbooks

Detailed incident documentation:

* [docs/production-recovery-2026-07-09.md](docs/production-recovery-2026-07-09.md) - exact commands used to bring the failed environment back up.
* [docs/tailscale-swarm-recovery.md](docs/tailscale-swarm-recovery.md) - Tailscale login/update and worker capacity restoration.
* [docs/coreex-app.md](docs/coreex-app.md) - CoreEx-specific image, routing, wildcard subdomain, and debugging notes.
* [prod-docker/setup-swarm/COMMANDS.md](prod-docker/setup-swarm/COMMANDS.md) - swarm playbook reference. Read the destructive warnings before use.

## Tailscale And Capacity State From 2026-07-09

The 2026-07-09 recovery first restored public availability by scheduling app services on the manager, then restored Tailscale and worker capacity.

Final verified state:

1. Production manager and all seven production workers were logged back into Tailscale.
2. `docker node ls` showed all eight production nodes as `Ready`.
3. The separate RackNerd test swarm nodes in `prod-docker/setup-swarm/testinventory.ini` were also logged back into Tailscale and showed `Ready`.
4. Stateless app services were moved off the manager and constrained to the `app_runtime=true` RackNerd workers.
5. `viralreel-db-vwkfbt`, `dokploy`, `dokploy-postgres`, and `dokploy-redis` stayed manager-pinned.
6. `racknerd-66b5b59` is Tailscale/Swarm `Ready` but is excluded from app placement because image pull failed with `No space left on device`; direct SSH showed `/dev/vda2` at `19G/19G`, `100%` full. Cleanup needs explicit approval.

Check Tailscale:

```bash
ansible -i prod-docker/setup-swarm/inventory.ini all -m shell -a \
  'hostname; systemctl is-active tailscaled || true; tailscale status --self 2>/dev/null || true; tailscale ip -4 2>/dev/null || true'
```

Worker-only rejoin pattern:

```bash
# on the manager
sudo docker swarm join-token worker

# on each worker only
sudo docker swarm leave --force
sudo docker swarm join --token <worker-token> --advertise-addr <worker-tailscale-ip> 100.73.236.49:2377
```

Current app placement guard:

```bash
docker node inspect racknerd-dd44635 --format '{{json .Spec.Labels}}'
docker node inspect racknerd-fb9a7f4 --format '{{json .Spec.Labels}}'

for s in buildinpublic-app-b37nff coreex-app-70cz87 jbaba-blog-hq29mq serivcehq-web-wpqe73 viralreel-appapi-rad4ao viralreel-appclient-vopczf viralreel-lending-erhdij; do
  sudo docker service inspect "$s" --format '{{json .Spec.TaskTemplate.Placement.Constraints}}'
done
```

Expected app constraints include `node.role==worker`, `node.labels.app_runtime==true`, and `node.hostname != racknerd-66b5b59`.
