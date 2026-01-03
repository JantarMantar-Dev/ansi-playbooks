# Update Swarm Playbook Usage

## 1. Normal Update / Repair
Runs standard checks. Fixes nodes that are Down or missing the correct logic.
```bash
ansible-playbook -i inventory.ini update-swarm.yml
```

## 2. Force Re-Initialization
Forces all NON-LEADER nodes (managers and workers) to leave the swarm and re-join.
**Use this if:** Nodes are stuck, have split-brain, or advertising wrong addresses.
```bash
ansible-playbook -i inventory.ini update-swarm.yml -e "force_swarm_reinit=true"
```

## 3. Verify Health Only
(Although verify runs at the end of the playbook, you can run a dry-run or specific tag if we added tags, but currently just run the playbook).

### Notes
- **Leader Safety**: The playbook identifies the active leader and skips 'force leave' on it to preserve the Swarm State.
- **Address Verification**: The playbook automatically repairs nodes that fail the `docker info | grep Advertise` check.
