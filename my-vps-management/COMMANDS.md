# Directory Management Commands

This playbook creates directories from a predefined list. It skips directories that already exist.

## Run with default directories
```bash
ansible-playbook -i inventory.ini create_directories.yml
```

## Run with custom directories
You can override the `dirs` variable from the command line:
```bash
ansible-playbook -i inventory.ini create_directories.yml -e '{"dirs": ["/path/one", "/path/two"]}'
```

## Dry Run (Verify without changes)
```bash
ansible-playbook -i inventory.ini create_directories.yml --check
```

# Safe Docker Cleanup Schedule

Apply the recipe to every production node:

```bash
ansible-playbook -i ../prod-docker/setup-swarm/inventory.ini docker_prune_cron.yml
```

It installs a weekly systemd timer at 03:17 on Sunday, with jitter to avoid a fleet-wide prune at once. It removes only stopped containers, images unused by every container, builder cache older than seven days, and journal entries older than fourteen days. It never prunes volumes or networks. See [recurring node maintenance](../docs/recurring-node-maintenance.md) for the policy and verification command.

# Port Management & Hardening

This playbook manages UFW firewall rules, specifically for hardening by removing public access to mail and swarm ports while ensuring Tailscale access is preserved.

## Run Playbook (Harden / Default)
```bash
ansible-playbook -i inventory.ini port_management.yml
```

## Run Playbook (Revert / Open Ports)
```bash
ansible-playbook -i inventory.ini port_management.yml -e "mode=revert"
```

# UFW-Docker Setup

This playbook installs and configures `ufw-docker` to solve the issue where Docker bypasses UFW rules by manipulating iptables directly.

## Run Playbook
```bash
ansible-playbook -i inventory.ini ufw_docker_setup.yml
```

## Idempotency
Checked via:
1. `stat` on `/usr/local/bin/ufw-docker` (skips download if present).
2. `grep` check on `/etc/ufw/after.rules` (skips install/reload if rules exist).

# Secure Networking (Unified)

This playbook is the "Master Switch" for network security. It runs both **Port Management** and **UFW-Docker Setup** together.

## Harden Mode (Default)
Safe to run repeatedly.
- Sets base ports (SSH, HTTP, HTTPS) + Routing.
- Removes extra ports (Mail, Swarm public access).
- Installs `ufw-docker` patch.
```bash
ansible-playbook -i inventory.ini secure_networking.yml
```

## Revert Mode (Undo All)
Use this if you locked yourself out (via Console) or need to debug.
- Restores extra ports.
- Removes `ufw-docker` patch (deletes rules, uninstalls binary).
```bash
ansible-playbook -i inventory.ini secure_networking.yml -e "mode=revert"
```
