# VPS Deploy

Operations repository for the remote Docker Swarm, Dokploy, VPS management, and app-specific production recovery notes.

## Quick Links

General operations:

* [Remote Docker environment](remote-docker-env.md)
* [Dokploy upgrade runbook](docs/dokploy-upgrade.md)
* [Production recovery: 2026-07-09](docs/production-recovery-2026-07-09.md)
* [Tailscale swarm recovery](docs/tailscale-swarm-recovery.md)
* [Agent/operator guide](AGENTS.md)
* [Ansible command index](ANSIBLE_COMMANDS.md)
* [VPS hardening guide](VPS_HARDENING_GUIDE.md)

App-specific docs:

* [CoreEx operations](docs/coreex-app.md)
* [Traefik/Docker Swarm 502 recovery](docs/traefik-swarm-502-runbook.md)
* [ViralReel commands](viralreel/COMMANDS.md)
* [OpenObserve commands](prod-docker/apps/openobserve/COMMANDS.md)

Infrastructure:

* [Swarm setup and repair commands](prod-docker/setup-swarm/COMMANDS.md)
* [Tailscale recovery playbook](prod-docker/setup-swarm/tailscale-recovery.yml)
* [Swarm inventory](prod-docker/setup-swarm/inventory.ini)
* [Dokploy bootstrap script](prod-docker/setup-swarm/dokploy.sh)
* [VPS management commands](my-vps-management/COMMANDS.md)
* [Docker login setup playbook](prod-docker/scripts/README.md)

Scripts:

* [Remote Docker debug helper](scripts/infra/debug-ssh-manager.sh)

## Common Commands

Check all hosts:

```bash
ansible -i prod-docker/setup-swarm/inventory.ini all -m ping
```

Debug the manager and CoreEx service:

```bash
./scripts/infra/debug-ssh-manager.sh coreex-app
```

Debug all ViralReel services:

```bash
./scripts/infra/debug-ssh-manager.sh viralreel
```

Check public availability:

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

## Appendix: Documentation Map

| Need | Start here |
| :--- | :--- |
| Current remote Docker/Dokploy layout | [remote-docker-env.md](remote-docker-env.md) |
| Upgrade production Dokploy safely | [docs/dokploy-upgrade.md](docs/dokploy-upgrade.md) |
| Exact failed-env recovery commands from 2026-07-09 | [docs/production-recovery-2026-07-09.md](docs/production-recovery-2026-07-09.md) |
| Restore Tailscale and worker swarm capacity | [docs/tailscale-swarm-recovery.md](docs/tailscale-swarm-recovery.md) |
| CoreEx wildcard routing and service details | [docs/coreex-app.md](docs/coreex-app.md) |
| A running Dokploy/Swarm app returns public `502` | [docs/traefik-swarm-502-runbook.md](docs/traefik-swarm-502-runbook.md) |
| Swarm repair playbook options and warnings | [prod-docker/setup-swarm/COMMANDS.md](prod-docker/setup-swarm/COMMANDS.md) |
| Host inventory | [prod-docker/setup-swarm/inventory.ini](prod-docker/setup-swarm/inventory.ini) |
| VPS hardening and firewall notes | [VPS_HARDENING_GUIDE.md](VPS_HARDENING_GUIDE.md) |
| Ansible command overview | [ANSIBLE_COMMANDS.md](ANSIBLE_COMMANDS.md) |
| Operator/agent rules for this repo | [AGENTS.md](AGENTS.md) |
