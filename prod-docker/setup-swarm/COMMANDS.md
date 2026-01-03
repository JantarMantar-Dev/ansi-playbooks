# Update Swarm Playbook Usage

## 1. Normal Update / Repair
Runs standard checks. Fixes nodes that are Down or missing the correct logic.
```bash
ansible-playbook -i inventory.ini update-swarm.yml
```

## 2. Force Swarm Re-Init (Fix worker nodes)
Forces all NON-LEADER nodes (managers and workers) to leave the swarm and re-join.
**Use this if:** Nodes are stuck, have split-brain, or advertising wrong addresses.
```bash
ansible-playbook -i inventory.ini update-swarm.yml -e "force_swarm_reinit=true"
```

## 3. Force Leader Repair (Re-Init)
Forces the LEADER node to re-initialize the swarm. This generates new join tokens and can fix advertise address issues on the leader itself.
**Use this if:** The leader is active but advertising the wrong address or you need to rotate tokens.
```bash
ansible-playbook -i inventory.ini update-swarm.yml -e "force_leader_reinit=true"
```

### Full Swarm Migration to Tailscale
To move the entire swarm (Leader and all Workers) from Public IPs to Tailscale IPs:
```bash
ansible-playbook -i inventory.ini update-swarm.yml -e "force_swarm_reinit=true" -e "use_tailscale=true"
```
*(Note: This command will automatically detect the address mismatch and re-initialize the leader and reconnect workers on the Tailscale network.)*

## 4. Verify Health Only
(Although verify runs at the end of the playbook, you can run a dry-run or specific tag if we added tags, but currently just run the playbook).

### Notes
- **Leader Safety**: The playbook identifies the active leader and skips 'force leave' on it to preserve the Swarm State.
- **Address Verification**: The playbook automatically repairs nodes that fail the `docker info | grep Advertise` check.
