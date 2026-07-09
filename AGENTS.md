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

## Placement After Recovery

The normal cluster design is manager/worker: stateful Dokploy/data services stay on the manager and stateless public apps use only `node.role==worker`. Do not add `node.labels.app_runtime==true` as a new default. It was a temporary 2026-07-09 containment workaround when SSD workers had not passed overlay and capacity verification.

When a worker is unhealthy, drain that node rather than narrowing every app's placement. Return it to `Active` only after the post-recovery Tailscale, disk/image, overlay-canary, and public-route gates pass. Follow [docs/swarm-post-recovery-validation.md](docs/swarm-post-recovery-validation.md) before removing the temporary legacy label constraints currently present on public apps.

Current verified state: one manager and all seven production workers are `Ready Active`. The four SSD workers required worker-only rejoin with their Tailscale advertise addresses to repair stale overlay membership. `racknerd-66b5b59` required removal of unused images and exited no-volume containers before it could rejoin. All five repaired workers passed the manager-side overlay VIP canary.

After **every** node restart, Tailscale/Docker/kernel/firewall upgrade, or worker rejoin, run the mandatory gate in [docs/swarm-post-recovery-validation.md](docs/swarm-post-recovery-validation.md): confirm the expected 1-manager/7-worker count, correct Docker `Node Address`, overlay VIP canary, and public routes. `Ready` alone is insufficient.

## Recurring Disk Maintenance

Use [my-vps-management/docker_prune_cron.yml](my-vps-management/docker_prune_cron.yml) with the production inventory to schedule the safe weekly cleanup on every node. It may prune stopped containers, unused images, old builder cache, and aged journal logs only. Never add `--volumes`, volume deletion, or network pruning to scheduled maintenance. See [docs/recurring-node-maintenance.md](docs/recurring-node-maintenance.md).

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
* `docs/dokploy-upgrade.md` - Dokploy version research, backup, upgrade, verification, and rollback runbook.
* `docs/production-recovery-2026-07-09.md` - exact incident recovery commands and evidence.
* `docs/coreex-app.md` - CoreEx-specific app, wildcard routing, and image notes.
* `README.md` - index, quick links, and common commands.

## Dokploy Upgrade

Before changing the production Dokploy version, read [docs/dokploy-upgrade.md](docs/dokploy-upgrade.md). Repeat its research gate on the day of the change, pin the target version explicitly, and run only the update path of the upstream install script. Never run `curl -sSL https://dokploy.com/install.sh | sh` on the existing manager because the install path can leave and reinitialize the swarm.

Keep `dokploy-postgres`, `dokploy`, `/etc/dokploy`, and `dokploy-redis` intact during the upgrade. Redis may be unused on newer self-hosted Dokploy releases, but remove it only in a separate approved maintenance task after the upgraded instance is stable.

2026-07-09 upgrade lesson: Dokploy publishes host-mode port `3000` and only the manager can run it. Use `--detach=true --update-order stop-first` for future Dokploy service updates. If an attached Docker CLI prints repeated `no suitable node ... host-mode port already in use` after accepting the update, inspect `docker service ps dokploy`; Swarm may already be completing the stop-first restart.

## Style

* Keep docs command-first and recovery-oriented.
* Include exact paths, services, and expected outputs.
* Mark dangerous commands clearly.
* Do not store new secrets in this repo.
* Do not remove existing user changes unless explicitly asked.
