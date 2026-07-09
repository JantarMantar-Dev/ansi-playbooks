# Agent Guide

This lowercase file exists because some tools and prompts ask for `agent.md`; the canonical guide for this repository is [AGENTS.md](AGENTS.md).

For remote deployment login, Dokploy/Swarm setup, service discovery, and safe recovery procedures, start with [VPS Deploy](https://github.com/JantarMantar-Dev/ansi-playbooks) and its local [remote environment guide](remote-docker-env.md). Use the documented SSH key and manager access path there; do not guess credentials or run destructive recovery commands.

After any node restart, worker rejoin, or Docker/Tailscale/kernel/firewall upgrade, require the [post-recovery validation gate](docs/swarm-post-recovery-validation.md). Verify the production node count (one manager and seven workers), each worker's Tailscale advertise address, the `dokploy-network` overlay VIP canary, and public routes before treating the cluster as healthy.
