# Ansible Command Reference

Run these commands from the root or the respective directories as indicated.

## 1. Initial Setup for New Nodes (e.g., Racknerd)
**Goal**: Set up SSH keys on new nodes that currently use root passwords.
**Directory**: `my-vps-management`
```bash
ansible-playbook -i inventory.ini setup_racknerd.yml --ask-pass
```
*Note: You will be prompted to enter the root password.*

## 2. Hardening VPS Nodes
**Goal**: Apply security hardening (UFW, user setup, SSH config) to all servers.
**Directory**: `my-vps-management`
```bash
ansible-playbook -i inventory.ini harden_vps.yml
```

## 3. Docker Swarm Test Deployment
**Goal**: Deploy the test stack (Traefik + Hello World) to the Swarm.
**Directory**: `docker-swarm-test`
```bash
ansible-playbook -i inventory.ini docker-swarm-test.yml
```

## 4. Zot Registry Deployment
**Goal**: Deploy the Zot registry to the Swarm.
**Directory**: `zot`
```bash
ansible-playbook -i inventory.ini setup_zot.yml
```

## 5. Set Docker Prod Swarm
**Goal**: Deploy the production stack to the Swarm.
**Directory**: `prod-docker`
```bash
ansible-playbook -i inventory.ini setup-swarm.yml
```

## 6. Ad-Hoc Commands
**Ping all servers**:
```bash
ansible -i my-vps-management/inventory.ini all -m ping
```

**Check uptime**:
```bash
ansible -i my-vps-management/inventory.ini all -a "uptime"
```
