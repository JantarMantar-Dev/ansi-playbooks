# Recurring Node Maintenance

Install the safe weekly cleanup on the production manager and all workers:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini \
  my-vps-management/docker_prune_cron.yml
```

The root systemd timer runs at 03:17 every Sunday with up to 45 minutes of randomized delay, uses a lock, and writes output to the systemd journal.

It removes only:

* stopped containers;
* images unused by every container;
* builder cache older than seven days; and
* systemd journal entries older than fourteen days.

It never runs `docker system prune --volumes`, removes Docker volumes, or prunes networks. Those can delete production data or deployment infrastructure and require a separate approved maintenance task.

Verify all nodes:

```bash
ansible -i prod-docker/setup-swarm/inventory.ini all -m shell -a \
  'systemctl is-active docker-safe-cleanup.timer; systemctl list-timers docker-safe-cleanup.timer; df -h /; sudo docker system df'
```

Treat less than 5 GiB free space or more than 85% Docker-filesystem use as a maintenance warning. Drain the worker before it becomes full, run the safe cleanup, then complete the [post-recovery validation](swarm-post-recovery-validation.md) before returning it to application scheduling.
