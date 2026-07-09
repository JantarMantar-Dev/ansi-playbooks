# Agent Guide

This repo manages production infrastructure. Be conservative, inspect before acting, and preserve data.

## Production Safety

Never run destructive Docker or swarm commands during incident response unless the user explicitly approves and backups are understood.

Do not run:

```bash
docker system prune --volumes
docker volume rm ...
docker swarm leave --force   # on the manager
docker swarm init            # on the manager
ansible-playbook ... update-swarm.yml -e "force_leader_reinit=true"
```

Treat these as production data:

```text
dokploy-postgres
dokploy-redis
dokploy
viralreel-db-vwkfbt-data
/etc/dokploy
```

## Default Recovery Workflow

1. Read [remote-docker-env.md](remote-docker-env.md).
2. Check `git status --short --branch`.
3. Confirm SSH and Ansible reachability.
4. Check Tailscale before swarm repair: `tailscale status --self`, `tailscale ip -4`, and whether the manager can listen on its Tailscale swarm address.
5. Check `docker node ls`, `docker service ls`, service tasks, and logs.
6. Confirm database services and volumes are present before changing app services.
7. Prefer non-destructive service updates over swarm reinitialization.
8. Verify with public curls.
9. Document every command that changed production state.

## Swarm Capacity Requires Tailscale

The production swarm has used Tailscale addresses for node advertisement. If workers are `Down`, do not jump straight to swarm reinit. First use [docs/tailscale-swarm-recovery.md](docs/tailscale-swarm-recovery.md).

Safe order:

1. Audit Tailscale state on all nodes.
2. Restore DNS if logged-out Tailscale pinned `/etc/resolv.conf` to `100.100.100.100`.
3. Update Tailscale on one worker.
4. Log in the pilot worker and the manager.
5. Rejoin one worker.
6. Verify `docker node ls`.
7. Recover the remaining workers.
8. Rebalance services only after enough workers are `Ready`.

Never run manager `docker swarm leave --force` or `docker swarm init` just to fix logged-out Tailscale.

2026-07-09 final placement note: all production nodes returned to Tailscale and Docker `Ready`, but app traffic was stable only after constraining stateless app services to the two RackNerd app-runtime workers:

```bash
docker node update --label-add app_runtime=true racknerd-dd44635
docker node update --label-add app_runtime=true racknerd-fb9a7f4
```

The stateless app services now use `node.role==worker`, `node.labels.app_runtime==true`, and `node.hostname != racknerd-66b5b59`. Leave `dokploy`, `dokploy-postgres`, `dokploy-redis`, and `viralreel-db-vwkfbt` on the manager.

`racknerd-66b5b59` hit `No space left on device` during image pull and later could not create Ansible temp dirs. Do not run Docker prune or delete data there without explicit user approval; treat disk cleanup as a separate approved maintenance task.

## Tailscale Browser Login Approval

When a node needs browser login, stop and ask the user to authenticate the printed Tailscale URL. The agent may poll after asking, but must not pretend the login step is automatic.

Recommended manager gate:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  prod-docker/setup-swarm/tailscale-recovery.yml \
  --limit racknerd-fb2892c \
  -e "start_browser_login=true" \
  -e "wait_for_tailscale_login=true" \
  -e "tailscale_login_wait_seconds=300"
```

Proceed to worker rejoin only after `tailscale ip -4` on the manager returns the expected Tailscale address.

## Debug Helper

Use:

```bash
./scripts/infra/debug-ssh-manager.sh
./scripts/infra/debug-ssh-manager.sh coreex-app
./scripts/infra/debug-ssh-manager.sh viralreel
```

Optional overrides:

```bash
REMOTE_HOST=jbaba@107.175.69.159 ./scripts/infra/debug-ssh-manager.sh coreex-app
SSH_KEY=~/.ssh/ssdnode-2025 ./scripts/infra/debug-ssh-manager.sh servicehq
```

## Documentation Boundaries

Use these files for their intended scope:

* `remote-docker-env.md` - general environment, availability, safety, and shared infrastructure.
* `docs/production-recovery-2026-07-09.md` - exact incident recovery commands and evidence.
* `docs/coreex-app.md` - CoreEx-specific app, wildcard routing, and image notes.
* `README.md` - index, quick links, and common commands.

## Style

* Keep docs command-first and recovery-oriented.
* Include exact paths, services, and expected outputs.
* Mark dangerous commands clearly.
* Do not store new secrets in this repo.
* Do not remove existing user changes unless explicitly asked.
