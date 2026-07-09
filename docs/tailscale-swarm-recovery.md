# Tailscale Swarm Recovery

This runbook restores Tailscale connectivity for the Docker Swarm without rebuilding the swarm leader or touching production volumes.

Use this when `docker node ls` shows workers as `Down` and Tailscale reports `Logged out` or no Tailscale IPv4.

## Current Incident Context

On 2026-07-09:

* All workers were `Down` from the manager.
* `tailscaled` was active on all nodes, but every node reported `Logged out`.
* Several nodes still had stale Tailscale IPv4 values in Docker state.
* The manager Docker daemon was listening on `100.73.236.49:2377`, so workers cannot rejoin until the manager itself is logged back into Tailscale.
* `racknerd-dd44635` was used as the pilot worker. It was updated from Tailscale `1.92.3` to `1.98.8`, DNS was restored from `/etc/resolv.pre-tailscale-backup.conf`, and browser login brought it back online as `100.119.37.71`.
* The manager and all production workers eventually returned to `BackendState=Running`; Docker marked all eight production swarm nodes `Ready` without a worker leave/rejoin.
* The separate two-node RackNerd test swarm in `prod-docker/setup-swarm/testinventory.ini` was also restored:
  * `racknerd-cb12b78` was updated from Tailscale `1.92.5` to `1.98.8`, logged back in as `100.94.226.62`, and stayed the test-swarm leader.
  * `racknerd-d0d1c33` was already on Tailscale `1.98.8`, logged back in as `100.83.102.13`, and returned to `Ready`.
* During app rebalance, `racknerd-66b5b59` ran out of disk while pulling one app image and could not create Ansible temp dirs. Direct SSH showed `/dev/vda2` as `19G` used, `0` available, `100%` full. Do not prune it without explicit approval; exclude it from app placement until disk is reviewed.

## Sources

Official Tailscale references used for this recipe:

* Tailscale Linux install/update entry point: <https://tailscale.com/download/linux>
* Tailscale auth keys: <https://tailscale.com/docs/features/access-control/auth-keys>
* Secure auth key handling: <https://tailscale.com/docs/features/access-control/auth-keys/how-to/secure-auth-keys>
* `tailscale up` CLI options: <https://tailscale.com/docs/reference/tailscale-cli/up>

Key points:

* Auth keys allow remote login without a browser.
* Pass auth keys with an environment variable or Ansible extra var, never by committing them to this repo.
* `tailscale up --auth-key=<key>` authenticates a node.
* `--accept-dns=false` prevents logged-out Tailscale DNS from taking over `/etc/resolv.conf`.

## Safety Rules

Do not run these while restoring Tailscale:

```bash
docker swarm leave --force   # on the manager
docker swarm init            # on the manager
docker system prune --volumes
docker volume rm ...
```

Only workers should run `docker swarm leave --force`, and only after:

1. The manager has a working Tailscale IPv4.
2. The worker has a working Tailscale IPv4.
3. The worker can reach `100.73.236.49:2377`.
4. You have a fresh worker join token from the current manager.

## Audit All Nodes

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml
```

The playbook defaults to audit-only.

Manual equivalent:

```bash
ansible -i prod-docker/setup-swarm/inventory.ini all -m shell -a '
hostname
echo TS_SERVICE=$(systemctl is-active tailscaled 2>/dev/null || true)
echo TS_VERSION=$(tailscale version 2>/dev/null | head -n1 || true)
echo TS_IP=$(tailscale ip -4 2>/dev/null || true)
tailscale status --self 2>/dev/null || true
docker info 2>/dev/null | egrep "Swarm:| NodeID:| Node Address:| Is Manager:| Managers:|  Address:" || true
'
```

## Pilot Update: One Worker

Use a worker with no production database role. The pilot used here was `racknerd-dd44635`.

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit racknerd-dd44635 \
  -e "update_tailscale=true" \
  -e "disable_tailscale_dns=true"
```

What this does:

1. Runs `tailscale set --accept-dns=false`.
2. Restores `/etc/resolv.conf` from `/etc/resolv.pre-tailscale-backup.conf` when Tailscale left it pinned to `100.100.100.100`.
3. Runs `apt-get update`.
4. Upgrades only the `tailscale` package.
5. Restarts `tailscaled`.
6. Prints login state and any browser auth URL.

The playbook uses apt lock timeouts and must not remove apt lock files. If another apt process is running, wait for it to finish or rerun the playbook after it exits.

Pilot result from 2026-07-09:

```text
racknerd-dd44635
before: 1.92.3
after:  1.98.8
state:  Online after browser login
ip:     100.119.37.71
```

After the manager came back online, this pilot worker automatically returned to `Ready` in `docker node ls`; no worker leave/rejoin was needed for that node.

## Login Options

### Option A: Browser Login

Run the pilot update, then open the printed login URL in a browser where you can authenticate to the tailnet.

Future agents must stop here and ask the user to approve the browser login. Do not assume the agent can complete this step alone.

Interactive/waiting flow:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit racknerd-fb2892c \
  -e "start_browser_login=true" \
  -e "wait_for_tailscale_login=true" \
  -e "tailscale_login_wait_seconds=300"
```

The playbook prints the login URL, waits for the user to authenticate, then continues after `BackendState=Running` and `tailscale ip -4` returns an address. Both checks matter because logged-out nodes can still show stale Tailscale IPs.

`start_browser_login=true` wraps `tailscale up --accept-dns=false` in a timeout so it can print the login URL without hanging indefinitely.

The debug helper can do the same wait for one host:

```bash
REMOTE_HOST=jbaba@107.175.69.159 ./scripts/infra/debug-ssh-manager.sh --wait-tailscale-login 300
```

After login:

```bash
ansible -i prod-docker/setup-swarm/inventory.ini racknerd-dd44635 -m shell -a '
hostname
tailscale status --self
tailscale ip -4
'
```

### Option B: Auth Key Login

Generate a one-off or reusable auth key in the Tailscale admin console. Prefer one-off keys for emergency recovery.

Do not store the key in this repo.

Local shell pattern:

```bash
export TS_AUTH_KEY=$(cat)
# paste key, then Ctrl-D
```

Run on one node:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit racknerd-dd44635 \
  -e "auth_tailscale=true" \
  -e "tailscale_authkey=$TS_AUTH_KEY"
```

Then remove it from the shell:

```bash
unset TS_AUTH_KEY
```

## Manager Login Is Required

The manager currently advertises and listens on its old Tailscale address:

```text
100.73.236.49:2377
```

Before any worker can rejoin, the manager must be logged into Tailscale and able to answer on that address. On 2026-07-09 the manager was still logged out after the pilot succeeded, and the playbook printed a `https://login.tailscale.com/a/...` browser login URL for user approval.

This is a user-approval gate. The agent should ask the user to authenticate the manager, then poll for a Tailscale IP before attempting worker recovery.

Manager login with an auth key:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit racknerd-fb2892c \
  -e "auth_tailscale=true" \
  -e "tailscale_authkey=$TS_AUTH_KEY"
```

Verify:

```bash
ansible -i prod-docker/setup-swarm/inventory.ini racknerd-fb2892c -m shell -a '
hostname
tailscale ip -4
sudo ss -ltnp | egrep ":(2377|7946)"
docker node ls
'
```

## Rejoin One Worker

Only after manager and pilot worker Tailscale are healthy:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit racknerd-dd44635 \
  -e "rejoin_swarm_workers=true"
```

Manual equivalent:

```bash
# manager
sudo docker swarm join-token -q worker

# worker only
sudo docker swarm leave --force
sudo docker swarm join --token <worker-token> --advertise-addr <worker-tailscale-ip> 100.73.236.49:2377
```

Verify from the manager:

```bash
docker node ls
docker service ls
```

## Recover All Workers

After the pilot proves update, login, and rejoin:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit swarm_workers \
  -e "update_tailscale=true" \
  -e "disable_tailscale_dns=true" \
  -e "auth_tailscale=true" \
  -e "tailscale_authkey=$TS_AUTH_KEY"
```

Then rejoin workers:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit swarm_workers \
  -e "rejoin_swarm_workers=true"
```

In the 2026-07-09 recovery, browser login alone was enough after Tailscale came back. The workers automatically reappeared as `Ready`; no worker leave/rejoin was required.

## Recover Separate Test Swarm Nodes

Two RackNerd nodes live in `prod-docker/setup-swarm/testinventory.ini`, not the production swarm inventory:

```text
racknerd-cb12b78 ansible_host=192.227.145.230
racknerd-d0d1c33 ansible_host=104.168.54.183
```

They form a separate two-node test swarm. Use the same Tailscale recovery playbook for login/update, but do not pass `rejoin_swarm_workers=true` unless intentionally repairing that test swarm.

Audit:

```bash
ansible -i prod-docker/setup-swarm/testinventory.ini all -m shell -a '
hostname
echo TS_VERSION=$(tailscale version 2>/dev/null | head -n1 || true)
echo BACKEND=$(tailscale status --json 2>/dev/null | sed -n "s/.*\"BackendState\": \"\([^\"]*\)\".*/\1/p" | head -n1)
echo TS_IP=$(tailscale ip -4 2>/dev/null || true)
docker info 2>/dev/null | egrep "Swarm:| NodeID:| Node Address:| Is Manager:| Managers:" || true
docker node ls 2>/dev/null || true
'
```

Update only the old manager, if needed:

```bash
ansible-playbook -i prod-docker/setup-swarm/testinventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit racknerd-cb12b78 \
  -e "disable_tailscale_dns=true" \
  -e "update_tailscale=true" \
  -e "apt_lock_timeout=60"
```

Start browser login for both and ask the user to authenticate the printed URLs:

```bash
ansible-playbook -i prod-docker/setup-swarm/testinventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit "racknerd-cb12b78:racknerd-d0d1c33" \
  -e "start_browser_login=true"
```

Verify both nodes:

```bash
ansible -i prod-docker/setup-swarm/testinventory.ini all -m shell -a '
hostname
echo BACKEND=$(tailscale status --json 2>/dev/null | sed -n "s/.*\"BackendState\": \"\([^\"]*\)\".*/\1/p" | head -n1)
echo TS_IP=$(tailscale ip -4 2>/dev/null || true)
docker info 2>/dev/null | egrep "Swarm:| NodeID:| Node Address:| Is Manager:| Managers:" || true
docker node ls 2>/dev/null || true
'
```

## Rebalance Services After Workers Are Ready

Once `docker node ls` shows enough workers as `Ready`, move app services back under worker placement if desired:

```bash
services="buildinpublic-app-b37nff coreex-app-70cz87 jbaba-blog-hq29mq serivcehq-web-wpqe73 viralreel-appapi-rad4ao viralreel-appclient-vopczf viralreel-lending-erhdij"

for s in $services; do
  sudo docker service update --detach=true --constraint-add node.role==worker "$s"
done
```

In the 2026-07-09 recovery, plain `node.role==worker` briefly placed some app tasks on SSDNodes and public routes returned `502`. The stable final placement used an explicit app-runtime label on the two RackNerd workers that passed image pull and curl checks:

```bash
docker node update --label-add app_runtime=true racknerd-dd44635
docker node update --label-add app_runtime=true racknerd-fb9a7f4

for s in $services; do
  docker service update --with-registry-auth \
    --constraint-add node.role==worker \
    --constraint-add "node.hostname != racknerd-66b5b59" \
    --constraint-add node.labels.app_runtime==true \
    --detach=false "$s"
done
```

Keep `viralreel-db-vwkfbt`, `dokploy`, `dokploy-postgres`, and `dokploy-redis` manager-pinned. Do not move database services during app rebalance.

Force a controlled task refresh only after constraints are correct and public curls are healthy:

```bash
for s in $services; do
  sudo docker service update --detach=true --force "$s"
done
```

Verify:

```bash
docker service ls
for s in $services; do
  docker service ps --no-trunc "$s" | sed -n "1,10p"
done
```

Public curl check:

```bash
urls=(
  "https://coreex.in/"
  "https://buildinpublic.page/"
  "https://blog.jbaba.dev/"
  "https://servicehq.biz/"
  "https://getviralreel.com/"
  "https://app.getviralreel.com/"
  "https://api.getviralreel.com/"
  "https://dokploy.jbaba.dev/"
)

for u in "${urls[@]}"; do
  printf "%-34s " "$u"
  curl -k -L --max-time 25 -s -o /dev/null \
    -w "code=%{http_code} bytes=%{size_download} time=%{time_total}\n" "$u"
done
```

Final public verification from 2026-07-09 after app-runtime placement:

```text
https://coreex.in/               code=200
https://test.coreex.in/          code=404
https://buildinpublic.page/      code=200
https://www.buildinpublic.page/  code=403
https://blog.jbaba.dev/          code=200
https://servicehq.biz/           code=200
https://www.servicehq.biz/       code=200
https://getviralreel.com/        code=200
https://www.getviralreel.com/    code=200
https://app.getviralreel.com/    code=200
https://api.getviralreel.com/    code=404
https://dokploy.jbaba.dev/       code=200
```

`api.getviralreel.com` returning `404` for `GET /`, `test.coreex.in` returning an app `404`, and `www.buildinpublic.page` returning `403` are expected for this environment.
