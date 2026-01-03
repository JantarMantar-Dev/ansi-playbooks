# Docker Scripts

This directory contains utility scripts and playbooks for managing the Docker environment.

## Setup Docker Login

The `setup_docker_login.yml` playbook automates the process of logging into a private Docker registry on all servers.

### Usage

Run the playbook from the project root:

```bash
ansible-playbook -i my-vps-management/inventory.ini prod-docker/scripts/setup_docker_login.yml
```

### Parameters

The playbook will prompt you for the following information:

1.  **Registry URL**: The URL of your private registry (e.g., `registry.example.com`).
2.  **Registry Password**: The password for the `zotuser` account.

### What it does

1.  Logs into the specified Docker registry on all hosts defined in the inventory.
2.  Verifies the login was successful.
3.  Checks that the authentication config exists in `~/.docker/config.json`.
