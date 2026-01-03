# Docker Swarm Management Features

This playbook `update-swarm.yml` provides a robust, self-healing mechanism for managing a Docker Swarm cluster. It supports standard updates, auto-repairs, and forced re-initialization of both workers and leaders.

## Core Variable Options

| Variable | Default | Description |
| :--- | :--- | :--- |
| `use_tailscale` | `false` | If `true`, configures the Swarm to advertise and listen on the **Tailscale IP** (`tailscale0` interface). If `false`, uses the Public IP (`ansible_host`). |
| `force_swarm_reinit` | `false` | If `true`, forces **all worker/follower nodes** (non-leaders) to leave and re-join the swarm. Useful for fixing stuck workers. |
| `force_leader_reinit` | `false` | If `true`, performs a **Hard Reset** on the **Leader node**. It forces the leader to leave and re-initialize a fresh cluster. **WARNING: Destructive to cluster state!** |

---

## 1. Standard Health Check & Repair
**Use when:** You want to check cluster health and auto-repair "Down" nodes or nodes with address mismatches (e.g. switching from Public IP to Tailscale).

```bash
# Check and repair based on default config (Public IPs)
ansible-playbook -i inventory.ini update-swarm.yml

# Check and fix to ensure Tailscale usage
ansible-playbook -i inventory.ini update-swarm.yml -e "use_tailscale=true"
```

*   **Behavior**: Identifies the leader, checks advertised addresses. If a mismatch is found (e.g. node advertising 172.x.x.x instead of Tailscale IP), it triggers a targeted repair for that node.

## 2. Force Worker Re-Join (Fix Stuck Workers)
**Use when:** Worker nodes are "Ready" but behaving strangely, or if you suspect certificates are invalid. This does **not** reset the Leader.

```bash
ansible-playbook -i inventory.ini update-swarm.yml -e "force_swarm_reinit=true"
```

*   **Behavior**: All non-leader nodes execute `docker swarm leave --force` and then re-join using the current tokens.

## 3. Full Network Migration (Public IP -> Tailscale)
**Use when:** You have an existing swarm on Public IPs and want to migrate the **entire** cluster to Tailscale Private Networking for security.

```bash
ansible-playbook -i inventory.ini update-swarm.yml -e "use_tailscale=true"
```

*   **Behavior**:
    1.  Detects the Leader is advertising Public IP but should be on Tailscale.
    2.  **Hard Resets** the Leader (`leave --force` -> `init`) on the Tailscale IP.
    3.  Updates the Swarm Join Tokens.
    4.  Forces all Workers to leave and re-join the *new* Swarm using the new tokens and Tailscale address.

## 4. Hard Leader Reset (Emergency Fix)
**Use when:** The Leader node itself is corrupted, or "Managers Address" is persistently advertising the wrong IP even after updates (e.g., stuck on `172.17.0.1` or old Public IP).

```bash
ansible-playbook -i inventory.ini update-swarm.yml -e "force_leader_reinit=true"
```

*   **WARNING**: This destroys services, secrets, and configs! It creates a brand new Swarm ID.
*   **Behavior**:
    1.  Force Leader to Leave.
    2.  Initialize New Swarm on correct IP.
    3.  Refresh Tokens.
    4.  Re-join all workers to the new Swarm.

---

## Troubleshooting Output
The playbook runs a `Phase 7: Detailed Summary Log` at the end to confirm the final state.

**Example Success Output:**
```
Node: racknerd-fb2892c
Public IP: 107.175.69.159
Tailscale IP: 100.73.236.49
Worker Swarm Advertise Addr: 100.73.236.49    <-- Matches Tailscale
Managers Address: 100.73.236.49:2377          <-- Matches Tailscale
Status: PROCESSED
```

If `Managers Address` does not match the expected IP, use **Option 4 (Hard Leader Reset)**.
