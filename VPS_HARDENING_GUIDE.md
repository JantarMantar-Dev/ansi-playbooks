# VPS Hardening & Security Master Guide

This document outlines the security standard for our VPS infrastructure. It serves as both a roadmap for our Ansible automation and a checklist for manual verification.

## 1. User & Access Management
**Goal:** Eliminate the greatest vulnerability—password-based root access.

### 1.1 Non-Root Sudo User
*   **Why:** Running as root is dangerous; accidental commands can destroy the system.
*   **Status:** ✅ Implemented (`jbaba` user created).
*   **Verification:** `whoami` should return `jbaba`. `sudo whoami` should return `root`.

### 1.2 SSH Hardening
*   **Why:** The default SSH port (22) is scanned constantly by bots. Passwords are easily brute-forced.
*   **Configuration:**
    *   Disable Password Auth: `PasswordAuthentication no`
    *   Disable Root Login: `PermitRootLogin no` (Current setup uses `prohibit-password`, `no` is safer once sudo is confirmed).
    *   **[RECOMMENDED]** Use a non-standard port (e.g., `2222`) to reduce log noise, OR restrict Port 22 to Tailscale IP only.
*   **Command Verification:**
    ```bash
    # Run from your local machine
    ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no user@vps-ip
    # Output should be "Permission denied (publickey)"
    ```

## 2. Network Security & Firewall (The "Castle Walls")
**Goal:** Only expose strictly necessary ports. Management ports should never be public.

### 2.1 UFW (Uncomplicated Firewall)
*   **Why:** Blocks unauthorized connections.
*   **Current Status:** ✅ Active. Allowed: 22 (SSH), 80/443 (Web), 2377/7946/4789 (Docker Swarm), 587/465/993 (Mail).
*   **Critique:** Allowing port 22 globally exposes your SSH key to brute-force attempts.
*   **Best Practice:**
    *   **Public:** 80/HTTP, 443/HTTPS (for apps).
    *   **Private (Tailscale):** 22/SSH, 8080/Traefik Dashboard, 9000/Portainer.


### 2.2 The "Docker Bypass" Problem (CRITICAL)
*   **The Issue:** By default, Docker modifies `iptables` directly to map ports, **completely bypassing UFW**. If you run `docker run -p 8080:80`, port 8080 is open to the world, even if UFW says "DENY".
*   **The Fix:** Use `ufw-docker` to solve this issue without losing Docker's powerful networking features, or use strict `swam` binding.
*   **Implementation (handled by Ansible):**
    1.  Download `ufw-docker` to `/usr/local/bin/ufw-docker`.
    2.  Run `ufw-docker install` to update `/etc/ufw/after.rules`.
    3.  Reload UFW.
*   **Verification:**
    *   Deploy a test container: `docker run -d -p 8081:80 nginx`
    *   Try to access port 8081 from outside. It should be **BLOCKED**.
    *   Allow it specifically: `ufw route allow 8081/tcp` (if needed for public access).

### 2.3 Cleaning Up Unused Ports (Mail)
*   **Observation:** Ports 587, 465, 993 are currently open. If this specific VPS is **not** a mail server, these should be closed immediately.
*   **Remediation Commands:**
    ```bash
    sudo ufw delete allow 587/tcp
    sudo ufw delete allow 465/tcp
    sudo ufw delete allow 993/tcp
    sudo ufw reload
    # Repeat for v6 rules if necessary, or use 'sudo ufw status numbered' and 'sudo ufw delete <number>'
    ```


### 2.4 Tailscale VPN (Private Management Network)
*   **Why:** Exposing SSH or Database ports to the internet is risky. Tailscale creates a private mesh network.
*   **Strategy:**
    1.  Install Tailscale on all nodes.
    2.  Bind SSH/Management tools to the **Tailscale Interface (tailscale0)** only.
    3.  Configure UFW to allow all traffic on `tailscale0`.
    *   **Command:** `sudo ufw allow in on tailscale0`

### 2.5 Docker Swarm Hardening (Restrict to Tailscale)
*   **Current State:** Swarm ports (2377, 7946, 4789) are open to the world.
*   **Recommendation:** Since nodes communicate via Tailscale, close these public ports.
*   **Action Commands:**
    ```bash
    # Ensure Tailscale traffic is trusted first
    sudo ufw allow in on tailscale0
    
    # Remove Public Swarm Rules
    sudo ufw delete allow 2377/tcp
    sudo ufw delete allow 7946/tcp
    sudo ufw delete allow 7946/udp
    sudo ufw delete allow 4789/udp
    
    sudo ufw reload
    ```


## 3. Intrusion Detection & Prevention
**Goal:** Detect active attacks and ban IPs automatically.

### 3.1 CrowdSec (Modern Fail2Ban)
*   **Why:** Collaborative security. If an IP attacks a user in France, your server blocks it instantly.
*   **Status:** ✅ Installed.
*   **Improvement:** Ensure the **Docker Collection** is installed so it sees attacks against your containers, not just SSH.

### 3.2 Fail2Ban
*   **Status:** ✅ Installed.
*   **Critique:** Running both CrowdSec and Fail2Ban is redundant and consumes RAM. CrowdSec is superior. **Recommendation:** Remove Fail2Ban and rely on CrowdSec.

## 4. System Maintenance & Integrity
**Goal:** Keep the foundation solid without manual intervention.

### 4.1 Unattended Upgrades
*   **Why:** Security patches (CVEs) are released daily. You will forget to update manually.
*   **Action Item:** Configure `unattended-upgrades` to auto-install security patches and reboot if necessary (at 3 AM).

### 4.2 Time Synchronization (NTP)
*   **Why:** Authentication (TOTP/Kerberos), Logs, and Cluster consensus (Docker Swarm) fail if clocks drift.
*   **Command:** `timedatectl set-ntp on`

## 5. Network Stack Hardening (Sysctl)
*   **Why:** The default Linux network stack is tuned for compatibility, not security.
*   **Action Items:**
    *   Disable IPv6 (if not used) to reduce attack surface.
    *   Disable IP Packet Forwarding (unless it's a router).
    *   Prevent IP Spoofing.
    *   Protect against SYN floods.

---

# Verification Plan (Do This After Deployment)

### 1. Public vs. Private Verification
We need to ensure "Public" services work for everyone, but "Management" services vanish.

**Test 1: Public Web (Should Work)**
```bash
curl -I https://your-domain.com
# Expect: HTTP 200 OK
```

**Test 2: SSH from Public Internet (Should FAIL)**
*Disconnect from Tailscale/VPN first.*
```bash
ssh user@public-ip
# Expect: Connection Timeout (if dropped) or Connection Refused
```

**Test 3: SSH from Tailscale (Should WORK)**
*Connect to Tailscale.*
```bash
ssh user@tailscale-ip
# Expect: Successful Login
```

**Test 4: Docker Firewall Leak Check**
Spin up a test container on a random port (e.g., 9999).
```bash
docker run -d -p 9999:80 nginx
```
From an **external** machine (not on VPN), try to access it:
```bash
curl http://public-ip:9999
```
*   **FAIL:** You see "Welcome to nginx!" (Docker bypassed firewall).
*   **PASS:** Connection Timeout.
