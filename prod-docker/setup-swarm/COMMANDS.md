# Docker Swarm Management Features

This playbook `update-swarm.yml` provides a robust, self-healing mechanism for managing a Docker Swarm cluster. It supports standard updates, auto-repairs, and forced re-initialization of both workers and leaders.

## Core Variable Options

| Variable | Default | Description |
| :--- | :--- | :--- |
| `use_tailscale` | `false` | If `true`, configures the Swarm to advertise and listen on the **Tailscale IP** (`tailscale0` interface). **Recommended: Always set to `true` for secure private networking.** |
| `force_swarm_reinit` | `false` | If `true`, forces **all worker/follower nodes** (non-leaders) to leave and re-join the swarm. Useful for fixing stuck workers or re-joining them to a new leader. |
| `force_leader_reinit` | `false` | If `true`, performs a **Hard Reset** on the **Leader node**. It forces the leader to leave and re-initialize a fresh cluster. **WARNING: Destructive to cluster state!** |

---

## 1. Standard Health Check & Repair
**Use when:** You want to check cluster health and auto-repair "Down" nodes or nodes with address mismatches (e.g. switching from Public IP to Tailscale).

```bash
# Recommended: Check and repair ensuring Tailscale usage
ansible-playbook -i inventory.ini update-swarm.yml -e "use_tailscale=true"
```

*   **Behavior**: Identifies the leader, checks advertised addresses. If a mismatch is found (e.g. node advertising Public IP instead of Tailscale IP), it triggers a targeted repair (`leave` -> `join`) for that node.

## 2. Force Worker Re-Join (Fix Stuck Workers)
**Use when:** Worker nodes are "Ready" but behaving strangely, or if you suspect certificates are invalid. This does **not** reset the Leader.

```bash
ansible-playbook -i inventory.ini update-swarm.yml -e "use_tailscale=true" -e "force_swarm_reinit=true"
```

*   **Behavior**: All non-leader nodes execute `docker swarm leave --force` and then re-join using the current tokens from the Leader.

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

## 4. Hard Leader Reset (Corruption Fix)
**Use when:** The Leader node itself is corrupted, or "Managers Address" is persistently advertising the wrong IP even after updates.

```bash
ansible-playbook -i inventory.ini update-swarm.yml -e "use_tailscale=true" -e "force_leader_reinit=true"
```

*   **WARNING**: This destroys services, secrets, and configs! It creates a brand new Swarm ID.
*   **Behavior**:
    1.  Force Leader to Leave.
    2.  Initialize New Swarm on Tailscale IP.
    3.  Refresh Tokens.
    4.  Re-join all workers to the new Swarm.

---

## 5. Manager Node Down / Recovery (Automatic)
**Use when:** The Swarm Manager's Docker is down, in `error` state, or the node was replaced/re-imaged and is no longer part of any swarm.

```bash
# Just run the standard command — Phase 1.5 auto-recovers the leader
ansible-playbook -i inventory.ini update-swarm.yml -e "use_tailscale=true"
```

*   **Behavior** (Phase 1.5: Auto-Recovery):
    1.  Phase 1 detects no healthy leader exists.
    2.  Phase 1.5 triggers on the first manager node:
        *   Force-leaves any broken/stale swarm state (`error`, `locked`, `active` with no leader).
        *   Initializes a **new Swarm** on the Tailscale IP.
        *   Retrieves fresh join tokens.
    3.  Phase 2&3 proceeds normally — all workers get `REPAIR` action (leave dead swarm → join new leader).

### If Manager Server is Unreachable
If the manager VPS itself is down (can't SSH), the playbook cannot run on it. You must:
1.  Fix or replace the server and ensure it's in `inventory.ini`.
2.  Install Docker and Tailscale on the new server.
3.  Run the playbook — auto-recovery will handle the rest.

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
