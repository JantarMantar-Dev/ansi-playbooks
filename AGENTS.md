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
4. Check `docker node ls`, `docker service ls`, service tasks, and logs.
5. Confirm database services and volumes are present before changing app services.
6. Prefer non-destructive service updates over swarm reinitialization.
7. Verify with public curls.
8. Document every command that changed production state.

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
