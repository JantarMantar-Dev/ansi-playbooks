# Swarm Post-Recovery Validation and Placement Policy

Use this checklist after a Tailscale, Docker Swarm, or Dokploy outage—and before treating the cluster as fully restored.

## Intended Steady State

This is a manager/worker Swarm. The normal placement policy is deliberately simple:

| Workload | Normal placement |
| --- | --- |
| Dokploy, Dokploy Postgres/Redis, ViralReel database | `node.role==manager` |
| Stateless public applications | `node.role==worker` |

Do **not** add `node.labels.app_runtime==true` to new application deployments as a normal default. That label was an emergency containment measure during the 2026-07-09 Tailscale recovery; it is not part of the bootstrap recipe and it divides the worker pool artificially.

If a worker is unhealthy, quarantine that **node**, not every application:

```bash
# Approval-required production change: stops new tasks on an unhealthy worker
sudo docker node update --availability drain <node-name>

# Restore only after the checks in this document pass
sudo docker node update --availability active <node-name>
```

With failed nodes drained, normal app services retain the intended `node.role==worker` constraint and Swarm can use every healthy worker.

## Why Node Drain Survives Auto-Deploy

Dokploy stores an application's Swarm placement in its `placementSwarm` configuration and rebuilds the Docker service on deployment. A direct `docker service update --constraint-add ...` is therefore a live, temporary override: the next Dokploy auto-deploy can replace it.

The intended persistent Dokploy configuration for the public applications is only:

```json
{"Constraints":["node.role==worker"]}
```

Do not edit Dokploy's database to change that baseline. Node availability is part of the Swarm scheduler state, not an application service override. A worker set to `Drain` remains ineligible for new tasks after a Dokploy build/deploy, so automatic deployments continue to use only the workers that have passed validation.

On 2026-07-09, an automatic blog deploy demonstrated this behavior: Dokploy removed manually added `app_runtime` constraints, scheduled the blog on an SSD worker, and the public route returned `502`. The durable containment was to drain the four unvalidated SSD workers and the full-disk `racknerd-66b5b59` worker. The permanent repair rejoined each worker to the existing manager with its Tailscale advertise address, verified an overlay VIP canary, removed stale node records, and then returned every validated worker to `Active`. The blog then ran with its normal `node.role==worker` specification and returned `200`.

## Why This Exists

`docker node ls` reporting `Ready` verifies Swarm membership and control-plane reachability. It does not prove that a node can participate in the `dokploy-network` overlay data path, pull private images, start containers with sufficient disk, or receive a Traefik request from the manager.

During the 2026-07-09 recovery, some services scheduled on SSD workers were locally healthy but their public routes returned `502`. Two RackNerd nodes were temporarily labelled `app_runtime=true` to contain impact while the wider worker pool was unverified. That was a safe emergency workaround, not the desired permanent topology.

## Recovery Completion Gate

Do not restore normal app placement merely because all nodes are `Ready`. Complete every gate below first.

## Mandatory Gate After Any Node Restart or Upgrade

Run this gate after a Docker, Tailscale, kernel, firewall, or OS upgrade; after a node restart; and after any worker rejoin. It is also required before calling a Dokploy upgrade complete.

The production topology is exactly **eight nodes**: one manager (`racknerd-fb2892c`) and seven workers. The two hosts in `testinventory.ini` are a separate test swarm and do not count toward this gate.

1. From the manager, confirm exactly one leader and seven `Ready Active` workers:

   ```bash
   ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 'sudo docker node ls'
   ```

2. On the restarted/upgraded worker, confirm Docker advertises its current Tailscale address—not `172.17.0.1`, a public IP, or a stale address:

   ```bash
   tailscale ip -4
   docker info | egrep 'Swarm:|NodeID:|Node Address:|Manager Addresses:'
   ```

3. Run the overlay canary in this document against that worker. It must return HTTP `200` through the `dokploy-network` service VIP.

4. If the canary fails, immediately set the node to `Drain`, then rejoin that **worker only** to the existing manager using its Tailscale address:

   ```bash
   # Manager: keep the token private.
   sudo docker swarm join-token -q worker

   # Worker only: never run this on the manager.
   sudo docker swarm leave --force
   sudo docker swarm join --token <worker-token> \
     --advertise-addr <worker-tailscale-ip> \
     100.73.236.49:2377
   ```

   Remove the old `Down` node record only after the replacement node is `Ready` and passes the canary. Do not reinitialize or force-leave the manager.

5. Return the worker to `Active` only after all prior checks pass, then run the public-route matrix.

### 1. Control Plane and Tailscale

```bash
ansible -i prod-docker/setup-swarm/inventory.ini all -m shell -a '
hostname
echo TS_SERVICE=$(systemctl is-active tailscaled 2>/dev/null || true)
echo TS_IP=$(tailscale ip -4 2>/dev/null || true)
echo TS_STATE=$(tailscale status --json 2>/dev/null | sed -n "s/.*\"BackendState\": \"\([^\"]*\)\".*/\1/p" | head -n1)
docker info --format "Swarm={{.Swarm.LocalNodeState}} NodeAddr={{.Swarm.NodeAddr}}" 2>/dev/null || true
'

ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 'sudo docker node ls'
```

Pass criteria:

* Every production node reports Tailscale `Running` with its expected Tailscale IPv4.
* Every node reports Swarm `active` and its Docker node address is its Tailscale address.
* The manager lists the intended nodes as `Ready`.

### 2. Capacity and Image Access

```bash
ansible -i prod-docker/setup-swarm/inventory.ini swarm_workers -m shell -a '
hostname
df -h / /var/lib/docker 2>/dev/null || true
sudo test -r /root/.docker/config.json && echo ROOT_DOCKER_AUTH=present || echo ROOT_DOCKER_AUTH=missing
'
```

Pass criteria:

* No worker filesystem used for Docker is full. Treat less than 5 GiB free or more than 85% used as a maintenance warning; do not schedule new app tasks there until reviewed.
* Root Docker registry credentials are present where private images must be pulled.

Do not solve a full filesystem with `docker system prune --volumes` during recovery. Drain the node and schedule a separate approved disk-maintenance task.

### 3. Overlay and Public-Traffic Canary

For each worker that was down, quarantined, or otherwise suspect, run one controlled canary before returning it to `Active` scheduling. The canary must prove the manager-side overlay can reach an application task on that worker.

Use a disposable service name and remove it immediately after the test. This is a production change; run it only in an approved recovery window.

```bash
NODE=<node-name>
CANARY=overlay-canary-$(date +%s)

# Manager: schedule a disposable HTTP service on exactly one worker.
sudo docker service create --detach=true \
  --name "$CANARY" \
  --network dokploy-network \
  --constraint "node.hostname==$NODE" \
  nginx:alpine

# Wait until the task is Running, obtain its service VIP, then request it from dokploy-network.
sudo docker service ps --no-trunc "$CANARY"
vip=$(sudo docker service inspect "$CANARY" \
  --format '{{range .Endpoint.VirtualIPs}}{{.Addr}}{{end}}' | cut -d/ -f1)
sudo docker run --rm --network dokploy-network curlimages/curl:8.12.1 \
  -fsS --max-time 15 "http://$vip/" >/dev/null

# Always remove the disposable service after the result is captured.
sudo docker service rm "$CANARY"
```

If the canary cannot be reached, keep that worker drained and investigate its Docker overlay/VXLAN, Tailscale state, UFW rules, and disk health. Do not work around it by adding `app_runtime` constraints to every app.

### 4. Restore the Baseline Placement

Only after every worker passes the applicable gates, remove temporary label constraints from each stateless application. First inspect the live service; do not assume a Dokploy screen matches Docker's current specification.

```bash
services="buildinpublic-app-b37nff coreex-app-70cz87 jbaba-blog-hq29mq serivcehq-web-wpqe73 viralreel-appapi-rad4ao viralreel-appclient-vopczf viralreel-lending-erhdij"

for s in $services; do
  sudo docker service inspect "$s" \
    --format '{{.Spec.Name}} constraints={{json .Spec.TaskTemplate.Placement.Constraints}}'
done
```

If all workers are validated and temporary constraints are present, remove only those constraints:

```bash
for s in $services; do
  sudo docker service update --detach=true \
    --constraint-rm 'node.labels.app_runtime==true' \
    --constraint-rm 'node.hostname != racknerd-66b5b59' \
    "$s"
done
```

Keep `node.role==worker` on stateless apps. Keep stateful services manager-pinned. If `racknerd-66b5b59` or another node has not passed capacity checks, leave that **node** drained instead of preserving an app-wide exclusion.

In Dokploy, save the corresponding normal placement configuration for each application under **Advanced → Cluster Settings**, then make one controlled redeploy and repeat the inspection. This prevents a future deployment from reintroducing an unintended constraint set.

### 5. Final Verification

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 '
sudo docker node ls
for s in buildinpublic-app-b37nff coreex-app-70cz87 jbaba-blog-hq29mq serivcehq-web-wpqe73 viralreel-appapi-rad4ao viralreel-appclient-vopczf viralreel-lending-erhdij; do
  sudo docker service ps --no-trunc "$s" | sed -n "1,3p"
  sudo docker service inspect "$s" --format "{{.Spec.Name}} constraints={{json .Spec.TaskTemplate.Placement.Constraints}}"
done
'

for u in https://coreex.in/ https://buildinpublic.page/ https://blog.jbaba.dev/ https://servicehq.biz/ https://getviralreel.com/ https://app.getviralreel.com/ https://api.getviralreel.com/; do
  printf '%-34s ' "$u"
  curl -k -L --max-time 25 -s -o /dev/null \
    -w 'code=%{http_code} bytes=%{size_download} time=%{time_total}\n' "$u"
done
```

Record the node status, canary result, disk result, final service constraints, and public curl results in the incident notes. A recovery is not complete until the worker pool and public traffic both pass.
