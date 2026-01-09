# Docker Swarm Test Setup

This directory contains the Ansible playbook and configuration for testing Docker Swarm setups.

## Playbook: `docker-swarm-test.yml`

This playbook initializes a Docker Swarm, joins workers, and deploys a test stack. It supports configuring the Swarm advertisement address using either the default `ansible_host` or the Tailscale IP.

### Commands

Run these commands from within the `docker-swarm-test` directory:

#### 1. Default Setup (Standard IP)
Uses the `ansible_host` defined in `inventory.ini` for Swarm advertisement.

```bash
ansible-playbook -i inventory.ini docker-swarm-test.yml
```

#### 2. Tailscale Setup (Mesh VPN)
Uses the `tailscale0` interface IPv4 address for Swarm advertisement. This is useful for secure, encrypted communication between nodes over the Tailscale mesh network.

```bash
ansible-playbook -i inventory.ini docker-swarm-test.yml -e "use_tailscale=true"
```
