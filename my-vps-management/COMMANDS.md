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

# Docker Prune Cron Job

This playbook sets up a recurring cron job to clean up Docker system and builder state every 3 hours. It is configured to run specifically on the `racknerd-bd2de99` host.

## Purpose
- Reclaims disk space by removing unused Docker data.
- Prunes all unused images, containers, networks, and volumes (`docker system prune -a --volumes`).
- Clears the Docker build cache (`docker builder prune -a`).
- Maintains system hygiene automatically without manual intervention.

## Run Playbook
```bash
ansible-playbook -i inventory.ini docker_prune_cron.yml
```

## Details
- **Schedule**: Every 3 hours.
- **System Prune**: Runs at minute 0.
- **Builder Prune**: Runs at minute 5.
- **User**: root
- **Idempotency**: The playbook explicitly checks for the existence of the cron jobs by searching the crontab (`crontab -l | grep`) before attempting to set them. This ensures they are only configured if not already present.
