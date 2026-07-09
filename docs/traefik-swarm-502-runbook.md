# Traefik/Docker Swarm 502 Recovery Runbook

Use this runbook when a Dokploy-managed application reports a running Swarm task, but its public route returns `502 Bad Gateway`.

## What a 502 Means Here

Dokploy writes a Traefik route such as:

```yaml
loadBalancer:
  servers:
    - url: http://<swarm-service>:<port>
```

A public `502` means Traefik accepted the request but could not reach that service over the Swarm overlay. It does **not** prove that the image failed to start.

The 2026-07-09 incident had this exact profile:

* `jbaba-blog-hq29mq` showed `1/1` and its Nginx process returned local `200 OK`.
* `https://blog.jbaba.dev/` returned `502`.
* At the time of the incident, the service had only `node.role==worker`; the evidence did not establish which deployment action removed the temporary restrictions.
* Swarm placed it on an SSD worker that was not a peer of the manager's `dokploy-network` overlay.
* Other apps constrained to the approved RackNerd runtime workers continued to return `200`.

The initial containment used temporary app-runtime placement constraints. The permanent repair rejoined each affected worker with its Tailscale advertise address and verified an overlay VIP canary before returning it to `Active`. This is a placement/overlay reachability failure, not evidence that the Dokploy upgrade, TLS certificate, or application image is automatically at fault.

## Safety

Read [AGENTS.md](../AGENTS.md) and [remote-docker-env.md](../remote-docker-env.md) before changing production.

Do not respond to a `502` by reinitializing the manager swarm, leaving the manager, pruning Docker data, deleting networks, or restarting database-bearing services. Keep `dokploy`, `dokploy-postgres`, `dokploy-redis`, `viralreel-db-vwkfbt`, `/etc/dokploy`, and their volumes intact.

The repair section changes a single application's placement and replaces its task. Get explicit approval before using it.

## 1. Establish the Failure Boundary

Run the manager helper with the service name or a unique pattern:

```bash
./scripts/infra/debug-ssh-manager.sh <service-pattern>
```

Then capture the service task, placement, route file, overlay peers, and public response:

```bash
SERVICE=<service-name>
DOMAIN=https://<public-domain>/

ssh -i ~/.ssh/ssdnode-2025 -o BatchMode=yes -o StrictHostKeyChecking=no \
  jbaba@107.175.69.159 "
sudo docker service ps --no-trunc \"$SERVICE\"
sudo docker service inspect \"$SERVICE\" \
  --format 'Image={{.Spec.TaskTemplate.ContainerSpec.Image}} Constraints={{json .Spec.TaskTemplate.Placement.Constraints}} Networks={{json .Spec.TaskTemplate.Networks}} Update={{if .UpdateStatus}}{{.UpdateStatus.State}} {{.UpdateStatus.Message}}{{end}}'
sudo grep -R -l -E \"$SERVICE|<public-domain>\" /etc/dokploy/traefik/dynamic 2>/dev/null || true
sudo docker network inspect dokploy-network --format 'Peers={{json .Peers}}'
"

curl -k -L --max-time 25 -sS -o /dev/null \
  -w 'HTTP=%{http_code} bytes=%{size_download} time=%{time_total}\n' \
  "$DOMAIN"
```

Interpret the result before changing anything:

| Evidence | Meaning | Next step |
| --- | --- | --- |
| Task is not `Running` or replicas are below target | Scheduler/image/startup problem | Inspect service logs and task errors. |
| Local container probe fails | Application/listener problem | Fix the image, command, or internal port. |
| Local container is `200`, public route is `502`, task node is absent from manager overlay peers | Placement/overlay problem | Continue with this runbook. |
| Route file is missing or points to the wrong service/port | Dokploy/Traefik configuration problem | Correct the app's Dokploy domain or port configuration, then redeploy. |

## 2. Prove the Container Is Healthy Locally

Obtain the running task's node from `docker service ps`, then SSH to that node. The local HTTP port is application-specific; static Nginx sites commonly use `80`, while many Node applications use `3000`.

```bash
SERVICE=<service-name>
PORT=<container-port>

ssh -i ~/.ssh/ssdnode-2025 -o BatchMode=yes -o StrictHostKeyChecking=no \
  jbaba@<task-node-ip> "
cid=\$(sudo docker ps --filter name=\"$SERVICE\" --format '{{.ID}}' | head -n1)
sudo docker ps --filter id=\"\$cid\" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
sudo docker exec \"\$cid\" sh -lc 'wget -S -O /dev/null -T 10 http://127.0.0.1:$PORT/'
"
```

If this returns `200` while the public URL returns `502`, do not rebuild the image. Continue to placement and overlay checks.

## 3. Check Worker Placement and Health

The intended normal constraint for a stateless public application is `node.role==worker`. `app_runtime=true` was a temporary recovery containment label, not the default design. A worker that cannot carry public traffic should be drained at the node level while it is repaired and tested.

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 '
sudo docker node inspect racknerd-dd44635 racknerd-fb9a7f4 \
  --format "{{.Description.Hostname}} status={{.Status.State}} labels={{json .Spec.Labels}} addr={{.Status.Addr}}"
sudo docker service inspect <service-name> \
  --format "{{json .Spec.TaskTemplate.Placement.Constraints}}"
'
```

Expected steady-state application constraint:

```text
node.role==worker
```

The live cluster still has legacy `app_runtime` and full-disk-node exclusion constraints from the July recovery. Do not copy those constraints to new applications. Follow [swarm-post-recovery-validation.md](swarm-post-recovery-validation.md) to validate workers, drain unhealthy nodes, and remove those temporary restrictions safely.

## 4. Quarantine a Failed Worker (Approval Required)

If a local-health/public-502 check identifies a specific worker as the failing data-path boundary, prevent new tasks from being scheduled there:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 '
sudo docker node update --availability drain <failed-worker>
'
```

Swarm will replace a task that can no longer run on the drained worker. Preserve the application's normal `node.role==worker` constraint. Return the node to `Active` only after it passes the post-recovery validation gates.

Do not use a new `app_runtime` label as a substitute for repairing or draining a failed worker. In Dokploy, save the ordinary worker placement configuration under **Advanced → Cluster Settings**, then make a controlled redeploy and confirm it with `docker service inspect`; Docker is the source of truth.

## 5. Verify the Full Path

```bash
SERVICE=<service-name>
DOMAIN=https://<public-domain>/

ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 "
sudo docker service ps --no-trunc \"$SERVICE\" | sed -n '1,8p'
sudo docker service inspect \"$SERVICE\" \
  --format 'Constraints={{json .Spec.TaskTemplate.Placement.Constraints}} Update={{if .UpdateStatus}}{{.UpdateStatus.State}} {{.UpdateStatus.Message}}{{end}}'
"

curl -k -L --max-time 25 -sS -o /dev/null \
  -w 'HTTP=%{http_code} bytes=%{size_download} time=%{time_total}\n' \
  "$DOMAIN"
```

Recovery is complete only when the service is at its intended replica count, the task is on an approved runtime worker, the constraints are present, and the public URL returns the expected response (normally `200`; an API root or intentional tenant-not-found route may validly return `404`).

## When Placement Is Already Correct

If the task is already on an approved app-runtime worker and the public route is still `502`, do not change unrelated app services. Investigate, in order:

1. The app's local listener and container logs.
2. The generated route file under `/etc/dokploy/traefik/dynamic/`.
3. `dokploy-traefik` logs and its connection to `dokploy-network`.
4. Tailscale health and Swarm node readiness using [tailscale-swarm-recovery.md](tailscale-swarm-recovery.md).
5. Overlay/VXLAN firewall rules between the specific manager and worker nodes.

Document the service, task node, constraints, overlay peers, exact curl result, and every production-changing command in the incident record.
