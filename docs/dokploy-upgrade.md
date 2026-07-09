# Dokploy Upgrade Runbook

This runbook is for upgrading the existing production Dokploy control plane without rebuilding the swarm or removing any production data.

Current observed production state on 2026-07-09:

```text
manager: racknerd-fb2892c / 107.175.69.159
previous Dokploy version before 2026-07-09 upgrade: v0.27.0
previous Dokploy service image before 2026-07-09 upgrade: dokploy/dokploy:latest@sha256:5a241a958a98b66f2e19052909e1eeedf776e680f5957211bd0d7ed28ccd5592
current Dokploy version after 2026-07-09 upgrade: v0.29.11
current Dokploy service image after 2026-07-09 upgrade: dokploy/dokploy:v0.29.11
target researched latest stable: v0.29.11
dokploy service placement: node.role == manager
dokploy-traefik image: traefik:v3.6.1
critical Dokploy data: dokploy-postgres volume, dokploy volume, /etc/dokploy
legacy service still present before upgrade: dokploy-redis
```

## Research Gate

Always repeat this research gate on the day of the upgrade. Do not assume the version in this file is still current.

1. Check the latest Dokploy release:

```bash
curl -fsSL -o /dev/null -w '%{url_effective}\n' \
  https://github.com/Dokploy/dokploy/releases/latest
```

Expected on 2026-07-09:

```text
https://github.com/Dokploy/dokploy/releases/tag/v0.29.11
```

2. Read every release between the current version and the target:

```bash
open https://github.com/Dokploy/dokploy/releases
```

For the 2026-07-09 upgrade from `v0.27.0` to `v0.29.11`, confirm at least these caveats:

* `v0.29.3` included a security note for self-hosted instances. If the current version is below `v0.29.3`, include the official security script step after the Dokploy image update and before declaring the upgrade complete.
* `v0.29.9` changed self-hosted Redis behavior. Official troubleshooting now says self-hosted instances older than `v0.29.9` show `dokploy-redis`, but Redis is no longer used in self-hosted Dokploy since `v0.29.9`. Do not delete the `dokploy-redis` service or volume during the upgrade window; treat removal as a later maintenance task after the upgraded instance has been stable.
* Dokploy does not update `dokploy-traefik` automatically. Leave Traefik unchanged during the Dokploy upgrade unless a separate Traefik upgrade has been researched, approved, and tested.
* The upstream install script has two paths. `sh -s update` pulls the image and runs `docker service update --image ... dokploy`. The plain install path can run `docker swarm leave --force` and `docker swarm init`; never run the plain install path on the existing production manager.
* On this swarm, Dokploy publishes port `3000` in host mode and only the manager can run the service. Future upgrades should use `--detach=true --update-order stop-first` so Docker does not sit in a misleading `no suitable node ... host-mode port already in use` wait loop while the old task still owns port `3000`.

Reference pages checked on 2026-07-09:

* <https://docs.dokploy.com/docs/core/installation>
* <https://docs.dokploy.com/docs/core/manual-installation>
* <https://docs.dokploy.com/docs/core/troubleshooting>
* <https://github.com/Dokploy/dokploy/releases>

## Safety Rules

Do not run any of these as part of a Dokploy version upgrade:

```bash
docker system prune --volumes
docker volume rm dokploy dokploy-postgres dokploy-redis
docker swarm leave --force   # on the manager
docker swarm init            # on the manager
curl -sSL https://dokploy.com/install.sh | sh
ansible-playbook ... update-swarm.yml -e "force_leader_reinit=true"
```

Do not paste raw `docker service logs dokploy` output into public issues or docs. On 2026-07-09 the logs contained backup command output with embedded object-storage credentials.

## Change Window Inputs

Set the target explicitly:

```bash
TARGET_DOKPLOY_VERSION=v0.29.11
REMOTE_HOST=jbaba@107.175.69.159
SSH_KEY=~/.ssh/ssdnode-2025
```

Use `latest` only for research. Use an explicit version for production execution so the runbook remains reproducible.

## Pre-Upgrade Checks

Run from this repo on the local machine:

```bash
git status --short --branch
ansible -i prod-docker/setup-swarm/inventory.ini racknerd-fb2892c -m ping
```

Run read-only checks on the manager:

```bash
ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no \
  -o ConnectTimeout=12 "$REMOTE_HOST" '
set -eu
echo "== host =="
hostname
date -Is

echo "== tailscale =="
tailscale status --self || true
tailscale ip -4 || true

echo "== swarm =="
sudo docker node ls
sudo docker service ls

echo "== dokploy service =="
sudo docker service inspect dokploy \
  --format "Image={{.Spec.TaskTemplate.ContainerSpec.Image}} Constraints={{json .Spec.TaskTemplate.Placement.Constraints}} Mounts={{json .Spec.TaskTemplate.ContainerSpec.Mounts}}"
sudo docker service inspect dokploy \
  --format "Env={{json .Spec.TaskTemplate.ContainerSpec.Env}}"
sudo docker service ps --no-trunc dokploy

echo "== dokploy containers =="
sudo docker ps --filter name=dokploy \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

echo "== version =="
cid=$(sudo docker ps --filter name=dokploy.1 --format "{{.ID}}" | head -n1)
sudo docker exec "$cid" sh -lc "node -e '\''try{console.log(require(\"./package.json\").version)}catch(e){process.exit(1)}'\''"

echo "== critical volumes =="
sudo docker volume ls --format "{{.Name}}" | egrep "^(dokploy|dokploy-postgres|dokploy-redis)$"

echo "== routes =="
sudo find /etc/dokploy/traefik/dynamic -maxdepth 1 -type f -name "*.yml" -print | sort
'
```

Public availability baseline:

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

* `https://api.getviralreel.com/` can return `404` for `GET /`.
* `https://test.coreex.in/` can return the CoreEx app-rendered tenant-not-found page as HTTP `404`.
* `https://www.buildinpublic.page/` previously returned `403` due to app-level host allowlist behavior.

## Backup Gate

Create a timestamped backup directory on the manager:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" '
set -eu
ts=$(date -u +%Y%m%dT%H%M%SZ)
backup_dir="/root/dokploy-upgrade-$ts"
sudo mkdir -p "$backup_dir"
sudo chmod 700 "$backup_dir"
echo "$backup_dir"
'
```

Back up `/etc/dokploy`, Docker service specs, and the Dokploy database:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" '
set -eu
backup_dir=$(sudo find /root -maxdepth 1 -type d -name "dokploy-upgrade-*" | sort | tail -n1)

sudo tar -C / -czf "$backup_dir/etc-dokploy.tgz" etc/dokploy

sudo docker service inspect dokploy dokploy-postgres dokploy-redis \
  > /tmp/dokploy-service-specs.json
sudo mv /tmp/dokploy-service-specs.json "$backup_dir/"

pg_cid=$(sudo docker ps --filter name=dokploy-postgres.1 --format "{{.ID}}" | head -n1)
sudo docker exec "$pg_cid" sh -lc \
  "pg_dump -U dokploy -d dokploy | gzip -c" \
  | sudo tee "$backup_dir/dokploy-postgres.sql.gz" >/dev/null

sudo ls -lh "$backup_dir"
'
```

Do not continue unless the backup files exist and are non-empty.

## Upgrade Execution

Download and inspect the release-pinned install script:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" "
set -eu
TARGET_DOKPLOY_VERSION=$TARGET_DOKPLOY_VERSION
curl -fsSL \
  \"https://github.com/Dokploy/dokploy/releases/download/\${TARGET_DOKPLOY_VERSION}/install.sh\" \
  -o /tmp/dokploy-install-\${TARGET_DOKPLOY_VERSION}.sh
grep -n \"update_dokploy\" /tmp/dokploy-install-\${TARGET_DOKPLOY_VERSION}.sh
grep -n \"docker service update --image\" /tmp/dokploy-install-\${TARGET_DOKPLOY_VERSION}.sh
"
```

Run the same safe update operation in a detached, stop-first form. This is intentionally equivalent to the upstream update path plus the rollout flags this production swarm needs:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" "
set -eu
TARGET_DOKPLOY_VERSION=$TARGET_DOKPLOY_VERSION
sudo docker pull dokploy/dokploy:\"\$TARGET_DOKPLOY_VERSION\"
sudo docker service update \
  --detach=true \
  --update-order stop-first \
  --image dokploy/dokploy:\"\$TARGET_DOKPLOY_VERSION\" \
  dokploy
"
```

If the current version is below `v0.29.3`, run the official security script after the service update:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" '
set -eu
curl -fsSL https://dokploy.com/security/0.29.3.sh -o /tmp/dokploy-security-0.29.3.sh
sudo bash /tmp/dokploy-security-0.29.3.sh
'
```

The security script also performs a `docker service update`. If it waits with repeated `no suitable node ... host-mode port already in use` messages after printing `Updating Dokploy service...`, detach from the local SSH command with `Ctrl-C` once the Docker service update has been accepted, then inspect the service:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" '
sudo docker service inspect dokploy \
  --format "Update={{if .UpdateStatus}}{{.UpdateStatus.State}} {{.UpdateStatus.Message}}{{else}}none{{end}} Env={{json .Spec.TaskTemplate.ContainerSpec.Env}} Secrets={{json .Spec.TaskTemplate.ContainerSpec.Secrets}}"
sudo docker service ps --no-trunc dokploy
'
```

Expected after the security script:

```text
BETTER_AUTH_SECRET_FILE=/run/secrets/dokploy-auth-secret
dokploy-auth-secret present in Docker secrets
```

## Post-Upgrade Verification

Watch rollout and confirm version:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" '
set -eu
sudo docker service ps --no-trunc dokploy
sudo docker service ls --filter name=dokploy
sudo docker ps --filter name=dokploy \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

cid=$(sudo docker ps --filter name=dokploy.1 --format "{{.ID}}" | head -n1)
sudo docker exec "$cid" sh -lc "node -e '\''console.log(require(\"./package.json\").version)'\''"
'
```

Check logs carefully, redacting secrets before sharing:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" '
sudo docker service logs --since 15m dokploy 2>&1 \
  | sed -E "s/(access-key-id=)[^[:space:]\"]+/\1REDACTED/g; s/(secret-access-key=)[^[:space:]\"]+/\1REDACTED/g" \
  | tail -200
'
```

Check that Dokploy still sees and manages the existing swarm services:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" '
set -eu
sudo docker service ls
for s in \
  dokploy \
  buildinpublic-app-b37nff \
  coreex-app-70cz87 \
  jbaba-blog-hq29mq \
  serivcehq-web-wpqe73 \
  viralreel-appapi-rad4ao \
  viralreel-appclient-vopczf \
  viralreel-lending-erhdij
do
  echo "== $s =="
  sudo docker service inspect "$s" \
    --format "Image={{.Spec.TaskTemplate.ContainerSpec.Image}} Constraints={{json .Spec.TaskTemplate.Placement.Constraints}} Update={{if .UpdateStatus}}{{.UpdateStatus.State}} {{.UpdateStatus.Message}}{{else}}none{{end}}"
  sudo docker service ps --no-trunc "$s" | sed -n "1,8p"
done
'
```

Repeat the public curl baseline from the pre-upgrade section. Dokploy is considered successfully upgraded only when:

* `dokploy` is `1/1`.
* The container package version equals `TARGET_DOKPLOY_VERSION`.
* `https://dokploy.jbaba.dev/` returns `200`.
* Existing public app routes match their pre-upgrade status.
* `dokploy-postgres` remains `1/1`.
* Existing app services and dynamic Traefik files are still present.
* The Dokploy UI can list existing projects/services and initiate normal service monitoring without creating duplicate services.

## Rollback

Prefer fixing forward if the upgraded Dokploy container starts but the UI has a small issue.

If the Dokploy service cannot start and application routing is otherwise intact, roll back only the Dokploy image:

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" '
set -eu
sudo docker service update \
  --image dokploy/dokploy:latest@sha256:5a241a958a98b66f2e19052909e1eeedf776e680f5957211bd0d7ed28ccd5592 \
  dokploy
sudo docker service ps --no-trunc dokploy
'
```

If the database migration ran and rollback does not start cleanly, stop and use the backup gate artifacts. Do not manually edit the database under pressure.

## Follow-Up

After the upgrade has been stable for a separate maintenance window:

* Decide whether to remove the now-unused `dokploy-redis` service and volume. Do not do this in the upgrade window.
* Decide whether to upgrade `dokploy-traefik` from `v3.6.1` to the Dokploy docs example `v3.6.7` or a newer researched Traefik release. Treat that as a separate routing change with its own rollback plan.
* Fix the backup cleanup permission issue seen in Dokploy logs: backup deletion to Wasabi returned `AccessDenied` on 2026-07-09.

## Execution Record: 2026-07-09

This upgrade was executed on 2026-07-09 from `v0.27.0` to `v0.29.11`.

Backup created on the manager:

```text
/root/dokploy-upgrade-20260709T145832Z
etc-dokploy.tgz             67M
dokploy-service-specs.json  16K
dokploy-postgres.sql.gz     46K
```

Observed before upgrade:

```text
dokploy                           1/1  dokploy/dokploy:latest@sha256:5a241a958a98b66f2e19052909e1eeedf776e680f5957211bd0d7ed28ccd5592
dokploy-postgres                  1/1  postgres:16
dokploy-redis                     1/1  redis:7
all eight swarm nodes             Ready
Dokploy package version           v0.27.0
```

Observed during upgrade:

* Pulling `dokploy/dokploy:v0.29.11` took roughly 12 minutes.
* Running the upstream `update` path accepted the image change but the attached Docker CLI repeatedly printed `no suitable node ... host-mode port already in use`. Detaching the client with `Ctrl-C` did not roll back the accepted update; Swarm then performed the existing `stop-first` update and started the new task.
* The official `0.29.3` security script migrated 1 existing 2FA record, created `dokploy-auth-secret`, and updated the Dokploy service. Its attached Docker CLI hit the same host-mode wait loop; after detaching, Swarm completed the restart.
* Health remained `starting` for about 60 to 100 seconds after each Dokploy restart before returning to `1/1`.

Observed after upgrade:

```text
dokploy                           1/1  dokploy/dokploy:v0.29.11
dokploy-postgres                  1/1  postgres:16
dokploy-redis                     1/1  redis:7
Dokploy package version           v0.29.11
Update state                      completed
BETTER_AUTH_SECRET_FILE           /run/secrets/dokploy-auth-secret
dokploy-auth-secret               present
```

Post-upgrade public checks matched the baseline:

```text
https://coreex.in/                     code=200
https://test.coreex.in/                 code=404
https://buildinpublic.page/            code=200
https://www.buildinpublic.page/        code=403
https://blog.jbaba.dev/                code=200
https://servicehq.biz/                 code=200
https://www.servicehq.biz/             code=200
https://getviralreel.com/              code=200
https://www.getviralreel.com/          code=200
https://app.getviralreel.com/          code=200
https://api.getviralreel.com/          code=404
https://dokploy.jbaba.dev/             code=200
```

Post-upgrade Dokploy logs showed:

```text
Postgres is reachable
Migration complete
Running DokployVersion: v0.29.11
Server Started on: http://0.0.0.0:3000
Starting Deployment Worker
```
