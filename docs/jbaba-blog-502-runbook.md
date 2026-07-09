# jbaba Blog: Deployed but Public Route Returns 502

Use this runbook when `https://blog.jbaba.dev/` returns `502 Bad Gateway` even though Dokploy shows the blog deployment as running.

## Symptom and Confirmed Cause

On 2026-07-09, the blog service was deployed and its Nginx container answered `200 OK` locally, but the public route returned `502` from Traefik.

```text
service: jbaba-blog-hq29mq
public route: https://blog.jbaba.dev/
image: zot.jbaba.dev/zotuser/jbaba-blog-hq29mq:latest
```

The service had only this placement constraint:

```text
node.role==worker
```

That allowed Swarm to schedule the task on `ssdnodes-6929d15592e99`. The task was healthy on that host, but `dokploy-network` on the manager did not have that SSDNode as an overlay peer. Traefik therefore could not reach the service VIP and returned `502`.

The two approved application-runtime workers are `racknerd-dd44635` and `racknerd-fb9a7f4`. They carry `app_runtime=true` and have passed image-pull and public-route checks. `racknerd-66b5b59` must remain excluded because its disk is full.

## Safety

These steps are read-only until **Repair placement**. Do not reinitialize the swarm, leave the manager, prune Docker data, or touch Dokploy/database services for this symptom. See [AGENTS.md](../AGENTS.md) and [remote-docker-env.md](../remote-docker-env.md) first.

The repair changes only the blog service placement and causes one controlled task replacement. Get explicit approval before running it.

## Diagnose

From this repository, use the manager helper:

```bash
./scripts/infra/debug-ssh-manager.sh jbaba-blog
```

Confirm all of the following:

```bash
ssh -i ~/.ssh/ssdnode-2025 -o BatchMode=yes -o StrictHostKeyChecking=no \
  jbaba@107.175.69.159 '
sudo docker service ls | grep jbaba-blog
sudo docker service ps --no-trunc jbaba-blog-hq29mq
sudo docker service inspect jbaba-blog-hq29mq \
  --format "Constraints={{json .Spec.TaskTemplate.Placement.Constraints}} Update={{if .UpdateStatus}}{{.UpdateStatus.State}} {{.UpdateStatus.Message}}{{end}}"
sudo docker network inspect dokploy-network --format "Peers={{json .Peers}}"
'

curl -k -L --max-time 25 -sS -o /dev/null \
  -w 'HTTP=%{http_code} bytes=%{size_download} time=%{time_total}\n' \
  https://blog.jbaba.dev/
```

The failure profile is:

* Service replicas show `1/1`, and the task state is `Running`.
* The public curl returns `HTTP=502`.
* The running node is not one of the labelled RackNerd app-runtime workers.
* The service constraints are missing `node.labels.app_runtime==true` and/or `node.hostname != racknerd-66b5b59`.

To rule out an application startup problem, probe the node that `docker service ps` reports for the running task. For the known incident it was `ssdnodes-6929d15592e99` (`104.225.219.149`):

```bash
ssh -i ~/.ssh/ssdnode-2025 -o BatchMode=yes -o StrictHostKeyChecking=no \
  jbaba@104.225.219.149 '
cid=$(sudo docker ps --filter name=jbaba-blog-hq29mq --format "{{.ID}}" | head -n1)
sudo docker ps --filter id="$cid" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
sudo docker exec "$cid" sh -lc "wget -S -O /dev/null -T 10 http://127.0.0.1/"
'
```

`200 OK` from the container plus public `502` confirms a routing/overlay placement failure, not a broken blog image.

## Repair Placement (Approval Required)

First confirm the expected labels and the blog's current constraints:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 '
sudo docker node inspect racknerd-dd44635 racknerd-fb9a7f4 \
  --format "{{.Description.Hostname}} labels={{json .Spec.Labels}}"
sudo docker service inspect jbaba-blog-hq29mq \
  --format "{{json .Spec.TaskTemplate.Placement.Constraints}}"
'
```

Only if the two required constraints are absent, add them without forcing an additional restart:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 '
sudo docker service update --detach=true --with-registry-auth \
  --constraint-add "node.labels.app_runtime==true" \
  --constraint-add "node.hostname != racknerd-66b5b59" \
  jbaba-blog-hq29mq
'
```

Do not use this command repeatedly: inspect constraints first to avoid adding duplicate rules. Do not remove `node.role==worker`.

## Verify Recovery

Wait for the service update, then verify task location, constraints, and the public route:

```bash
ssh -i ~/.ssh/ssdnode-2025 jbaba@107.175.69.159 '
sudo docker service ps --no-trunc jbaba-blog-hq29mq
sudo docker service inspect jbaba-blog-hq29mq \
  --format "Constraints={{json .Spec.TaskTemplate.Placement.Constraints}} Update={{if .UpdateStatus}}{{.UpdateStatus.State}} {{.UpdateStatus.Message}}{{end}}"
'

curl -k -L --max-time 25 -sS -o /dev/null \
  -w 'HTTP=%{http_code} bytes=%{size_download} time=%{time_total}\n' \
  https://blog.jbaba.dev/
```

Success means the service is `1/1`, its task runs on a labelled RackNerd worker, and the public curl returns `HTTP=200`.

If it is still `502` after correct placement, follow the broader [Tailscale/Swarm recovery guide](tailscale-swarm-recovery.md) to inspect overlay reachability before changing any other service.
