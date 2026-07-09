# Production Recovery: 2026-07-09

This document records exactly how the failed remote Docker/Dokploy environment was brought back up on 2026-07-09.

The recovery was intentionally non-destructive. No database volumes were removed, no prune commands were run, and the swarm leader was not reinitialized.

## Summary

The manager was reachable and data services were running, but all worker nodes were `Down` from the leader's view. Application services with `node.role==worker` constraints could not be scheduled.

Safe recovery path:

1. Confirm the manager and data services were healthy.
2. Confirm workers were unavailable and Tailscale was logged out or unhealthy.
3. Avoid leader reinitialization.
4. Pre-pull private Zot images on the manager using root Docker auth.
5. Temporarily remove worker-only placement constraints from public app services.
6. Let the services run on the manager.
7. Verify service replicas and public URLs with curl.
8. Document remaining follow-up to repair Tailscale and worker capacity.

## Initial Checks

The local SSH alias timed out, but the inventory IP worked:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=12 jbaba@racknerd-fb2892c 'hostname'
# timed out

ssh -i ~/.ssh/ssdnode-2025 -o BatchMode=yes -o StrictHostKeyChecking=no \
  -o ConnectTimeout=12 jbaba@107.175.69.159 'hostname; uptime'
```

Ansible showed the manager and most workers were reachable over normal SSH, but one worker had auth/temp issues:

```bash
ansible -i prod-docker/setup-swarm/inventory.ini all -m ping
```

Manager status:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 \
  'hostname; uptime; docker info --format "Swarm={{.Swarm.LocalNodeState}} NodeID={{.Swarm.NodeID}} IsManager={{.Swarm.ControlAvailable}}"; docker node ls; docker service ls'
```

Observed:

```text
Swarm=active
racknerd-fb2892c Ready Active Leader
all worker nodes Down
```

Important service state before recovery:

```text
dokploy                           1/1
dokploy-postgres                  1/1
dokploy-redis                     1/1
viralreel-db-vwkfbt               1/1
coreex-app-70cz87                 0/1
buildinpublic-app-b37nff          0/1
jbaba-blog-hq29mq                 0/1
serivcehq-web-wpqe73              0/1
viralreel-appapi-rad4ao           0/2
viralreel-appclient-vopczf        0/2
viralreel-lending-erhdij          0/2
```

## Root Cause Evidence

Inspect a failed app:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 \
  'docker service ps --no-trunc coreex-app-70cz87'
```

Observed scheduler error:

```text
no suitable node (7 nodes not available for new tasks; scheduling constraints not satisfied on 1 node)
```

Checked swarm/Tailscale state:

```bash
ansible -i prod-docker/setup-swarm/inventory.ini all -m shell -a \
  'hostname; docker info 2>/dev/null | egrep "Swarm:| NodeID:| Is Manager:| Node Address:| Managers:|  Address:" || true; ip -o addr show tailscale0 2>/dev/null | head -n1 || true'
```

Observed:

* The manager advertised a Tailscale address for swarm: `100.73.236.49:2377`.
* Several nodes were logged out of Tailscale.
* Some workers thought they were still active locally, but the manager marked them `Down`.

Checked the manager listener:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 \
  'sudo ss -ltnp | egrep ":(2377|7946|4789|3000)" || true; sudo ufw status verbose || true'
```

Observed:

```text
dockerd listening on 100.73.236.49:2377
dockerd listening on 100.73.236.49:7946
```

That meant the swarm was bound to Tailscale, but Tailscale was not consistently authenticated.

## Safety Decision

The existing swarm repair playbook documents that leader reinit is destructive to services, secrets, and configs. Because the manager and data services were alive, the recovery avoided:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini prod-docker/setup-swarm/update-swarm.yml -e "force_leader_reinit=true"
docker swarm leave --force   # on manager
docker swarm init            # on manager
docker system prune --volumes
```

The chosen fix was to schedule app services on the current healthy manager until Tailscale/workers can be repaired.

## Image Pull Issue

First attempt to remove the worker constraint on one app failed because the manager had not pulled that private image yet:

```bash
docker service update --constraint-rm node.role==worker buildinpublic-app-b37nff
```

Observed:

```text
No such image: zot.jbaba.dev/zotuser/buildinpublic-app-b37nff:latest
```

Plain user-level pull failed:

```bash
docker pull zot.jbaba.dev/zotuser/buildinpublic-app-b37nff:latest
```

Observed:

```text
pull access denied ... no basic auth credentials
```

Root Docker credentials existed:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 \
  'sudo ls -l /root/.docker/config.json /var/lib/docker/volumes/dokploy/_data/config.json; sudo grep -c zot.jbaba.dev /root/.docker/config.json'
```

Root pull succeeded:

```bash
sudo docker pull zot.jbaba.dev/zotuser/buildinpublic-app-b37nff:latest
```

## Recovery Commands Used

Run from local machine into the manager:

```bash
ssh -i ~/.ssh/ssdnode-2025 -o BatchMode=yes -o StrictHostKeyChecking=no \
  -o ConnectTimeout=12 jbaba@107.175.69.159 '
set -u
services="buildinpublic-app-b37nff coreex-app-70cz87 jbaba-blog-hq29mq serivcehq-web-wpqe73 viralreel-appapi-rad4ao viralreel-appclient-vopczf viralreel-lending-erhdij"

echo PREPULL
for s in $services; do
  img=$(sudo docker service inspect "$s" --format "{{.Spec.TaskTemplate.ContainerSpec.Image}}" | cut -d@ -f1)
  echo "=== pulling $s -> $img ==="
  sudo docker pull "$img" || echo "PULL_FAILED $s"
done

echo UPDATE_SERVICES
for s in $services; do
  echo "=== updating $s ==="
  constraints=$(sudo docker service inspect "$s" --format "{{json .Spec.TaskTemplate.Placement.Constraints}}")
  if echo "$constraints" | grep -q "node.role==worker"; then
    sudo docker service update --detach=true --with-registry-auth --constraint-rm node.role==worker "$s" || echo "UPDATE_FAILED $s"
  else
    sudo docker service update --detach=true --with-registry-auth --force "$s" || echo "UPDATE_FAILED $s"
  fi
  sleep 5
  sudo docker service ps --no-trunc "$s" | sed -n "1,7p"
done

echo FINAL_LS
sudo docker service ls
'
```

Notes:

* `--with-registry-auth` ensured the service update carried registry auth metadata.
* `--detach=true` returned control while Swarm rolled the update.
* The command changed service placement and task versions only.
* It did not remove any volume, database, secret, or route file.

## Post-Recovery Service Verification

After waiting for Swarm to roll the tasks:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 '
sudo docker service ls
for s in viralreel-appapi-rad4ao viralreel-appclient-vopczf viralreel-lending-erhdij coreex-app-70cz87 buildinpublic-app-b37nff jbaba-blog-hq29mq serivcehq-web-wpqe73; do
  echo "=== $s inspect ==="
  sudo docker service inspect "$s" --format "Update={{if .UpdateStatus}}{{.UpdateStatus.State}} {{.UpdateStatus.Message}}{{else}}none{{end}} Constraints={{json .Spec.TaskTemplate.Placement.Constraints}} Replicas={{if .Spec.Mode.Replicated}}{{.Spec.Mode.Replicated.Replicas}}{{end}}"
  sudo docker service ps --no-trunc "$s" | sed -n "1,10p"
done
'
```

Recovered replica counts:

```text
buildinpublic-app-b37nff          1/1
coreex-app-70cz87                 1/1
jbaba-blog-hq29mq                 1/1
serivcehq-web-wpqe73              1/1
viralreel-appapi-rad4ao           2/2
viralreel-appclient-vopczf        2/2
viralreel-lending-erhdij          2/2
dokploy                           1/1
dokploy-postgres                  1/1
dokploy-redis                     1/1
viralreel-db-vwkfbt               1/1
```

Some Node/Vite services took longer to listen even after Docker reported `Running`. Confirm inside containers before declaring them healthy:

```bash
for s in coreex-app-70cz87 serivcehq-web-wpqe73; do
  cid=$(sudo docker ps --filter name=$s --format "{{.ID}}" | head -n1)
  sudo docker exec "$cid" sh -lc 'date; netstat -ltnp || true; wget -S -O- -T 15 http://127.0.0.1:3000/ || true'
done
```

## Public Curl Verification

Run from local machine:

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
    -w "code=%{http_code} bytes=%{size_download} time=%{time_total}\n" "$u" || echo curl_failed
done
```

Final verified results:

```text
https://coreex.in/                     code=200
https://test.coreex.in/                code=404
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

Interpretation:

* `api.getviralreel.com` returning `404` for `GET /` is expected API behavior.
* `test.coreex.in` returning `404` is expected app-rendered tenant-not-found behavior.
* `www.buildinpublic.page` returning `403` is an app-level host allowlist issue. `buildinpublic.page` is up.

## Remaining Work

This recovery restored public availability but did not restore worker capacity.

Follow-up:

1. Re-auth Tailscale on the manager and logged-out workers.
2. Confirm `tailscale ip -4` works on every swarm node.
3. Rejoin workers to the existing manager. Do not reinitialize the manager.
4. Confirm `docker node ls` shows enough workers as `Ready`.
5. Decide whether to restore `node.role==worker` constraints.

Worker rejoin pattern:

```bash
# manager
sudo docker swarm join-token worker

# each worker only
sudo docker swarm leave --force
sudo docker swarm join --token <worker-token> --advertise-addr <worker-tailscale-ip> 100.73.236.49:2377
```

Restore worker constraints only after worker health is proven:

```bash
for s in buildinpublic-app-b37nff coreex-app-70cz87 jbaba-blog-hq29mq serivcehq-web-wpqe73 viralreel-appapi-rad4ao viralreel-appclient-vopczf viralreel-lending-erhdij; do
  sudo docker service update --constraint-add node.role==worker "$s"
done
```
