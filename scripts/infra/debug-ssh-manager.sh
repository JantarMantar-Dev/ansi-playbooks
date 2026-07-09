#!/usr/bin/env bash
set -u

# Debug remote Docker/Dokploy service state from the swarm manager.
# Usage:
#   ./scripts/infra/debug-ssh-manager.sh
#   ./scripts/infra/debug-ssh-manager.sh coreex-app
#   ./scripts/infra/debug-ssh-manager.sh --wait-tailscale-login 300
#   REMOTE_HOST=jbaba@107.175.69.159 ./scripts/infra/debug-ssh-manager.sh viralreel

REMOTE_HOST="${REMOTE_HOST:-jbaba@107.175.69.159}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ssdnode-2025}"
SERVICE_PATTERN="coreex-app"
WAIT_TAILSCALE_LOGIN=false
WAIT_TAILSCALE_SECONDS=300
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10)

while [ "$#" -gt 0 ]; do
  case "$1" in
    --wait-tailscale-login)
      WAIT_TAILSCALE_LOGIN=true
      if [ "${2:-}" != "" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        WAIT_TAILSCALE_SECONDS="$2"
        shift
      fi
      ;;
    --help|-h)
      sed -n '1,16p' "$0"
      exit 0
      ;;
    *)
      SERVICE_PATTERN="$1"
      ;;
  esac
  shift
done

if [ -f "$SSH_KEY" ]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

remote() {
  ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "$@"
}

section() {
  printf '\n--- %s ---\n' "$1"
}

echo "=========================================================="
echo " Remote Docker / Dokploy Debugger"
echo "=========================================================="
echo "Target remote host: $REMOTE_HOST"
echo "Service pattern:    $SERVICE_PATTERN"
echo "SSH key:            $SSH_KEY"
echo

section "SSH connection"
if ! remote "hostname; uptime" >/tmp/debug-ssh-manager-connect.$$ 2>&1; then
  cat /tmp/debug-ssh-manager-connect.$$
  rm -f /tmp/debug-ssh-manager-connect.$$
  echo "ERROR: Could not connect to $REMOTE_HOST."
  echo "Check SSH key, host alias/IP, firewall, and Tailscale status."
  exit 1
fi
cat /tmp/debug-ssh-manager-connect.$$
rm -f /tmp/debug-ssh-manager-connect.$$

section "Docker swarm node status"
remote "sudo docker node ls 2>&1 || docker node ls 2>&1"

section "Docker swarm services"
remote "sudo docker service ls 2>&1 || docker service ls 2>&1"

section "Manager containers"
remote "sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>&1 || docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>&1"

section "Critical volumes"
remote "sudo docker volume ls --format 'table {{.Name}}\t{{.Driver}}' 2>&1 | egrep 'dokploy|viralreel|maillayer|VOLUME|NAME' || true"

section "Tailscale status"
remote "systemctl is-active tailscaled 2>/dev/null || true; tailscale status --self 2>/dev/null || true; tailscale ip -4 2>/dev/null || true"

if [ "$WAIT_TAILSCALE_LOGIN" = true ]; then
  section "Tailscale browser login wait"
  backend="$(remote "tailscale status --json 2>/dev/null | sed -n 's/.*\"BackendState\": \"\\([^\"]*\\)\".*/\\1/p' | head -n1" | tr -d '\r')"
  auth_url="$(remote "tailscale status --json 2>/dev/null | sed -n 's/.*\"AuthURL\": \"\\([^\"]*\\)\".*/\\1/p' | head -n1" | tr -d '\r')"
  current_ip="$(remote "tailscale ip -4 2>/dev/null || true" | tr -d '\r')"
  if [ "$backend" = "Running" ] && [ -n "$current_ip" ]; then
    echo "Tailscale already has IPv4: $current_ip"
  else
    if [ -z "$auth_url" ]; then
      auth_url="$(remote "sudo tailscale up --accept-dns=false 2>&1 || true" | sed -n 's/.*\\(https:\\/\\/login.tailscale.com\\/a\\/[A-Za-z0-9]*\\).*/\\1/p' | head -n1 | tr -d '\r')"
    fi
    echo "ACTION REQUIRED: authenticate this node in Tailscale."
    echo "Open: ${auth_url:-'(no auth URL found; run tailscale status --json on the host)'}"
    echo "Polling for up to ${WAIT_TAILSCALE_SECONDS}s..."
    end_time=$((SECONDS + WAIT_TAILSCALE_SECONDS))
    while [ "$SECONDS" -lt "$end_time" ]; do
      backend="$(remote "tailscale status --json 2>/dev/null | sed -n 's/.*\"BackendState\": \"\\([^\"]*\\)\".*/\\1/p' | head -n1" | tr -d '\r')"
      current_ip="$(remote "tailscale ip -4 2>/dev/null || true" | tr -d '\r')"
      if [ "$backend" = "Running" ] && [ -n "$current_ip" ]; then
        echo "Tailscale login detected. IPv4: $current_ip"
        break
      fi
      sleep 5
    done
    if [ "$backend" != "Running" ] || [ -z "$current_ip" ]; then
      echo "Timed out waiting for Tailscale login."
      exit 2
    fi
  fi
fi

section "Matching services"
services="$(remote "sudo docker service ls --format '{{.Name}}' 2>/dev/null | grep '$SERVICE_PATTERN' || true" | tr -d '\r')"

if [ -z "$services" ]; then
  echo "No service matched pattern: $SERVICE_PATTERN"
  echo "Try one of: coreex-app, viralreel, buildinpublic, servicehq, jbaba-blog, dokploy"
  exit 0
fi

printf '%s\n' "$services"

for service in $services; do
  section "Service tasks: $service"
  remote "sudo docker service ps --no-trunc '$service' 2>&1 || docker service ps --no-trunc '$service' 2>&1"

  section "Service inspect: $service"
  remote "sudo docker service inspect '$service' --format 'Image={{.Spec.TaskTemplate.ContainerSpec.Image}} Constraints={{json .Spec.TaskTemplate.Placement.Constraints}} Replicas={{if .Spec.Mode.Replicated}}{{.Spec.Mode.Replicated.Replicas}}{{end}} Update={{if .UpdateStatus}}{{.UpdateStatus.State}} {{.UpdateStatus.Message}}{{else}}none{{end}}' 2>&1 || true"

  section "Service logs: $service"
  remote "sudo docker service logs --tail 80 '$service' 2>&1 | tail -n 100 || true"

  section "Live container probe: $service"
  remote "cid=\$(sudo docker ps --filter name='$service' --format '{{.ID}}' | head -n1); if [ -n \"\$cid\" ]; then sudo docker ps --filter id=\$cid --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'; sudo docker exec \$cid sh -lc 'ps aux | sed -n \"1,20p\"; echo PORTS; (netstat -ltnp || ss -ltnp || true) 2>/dev/null; echo LOCAL_HTTP; (wget -S -O- -T 8 http://127.0.0.1:3000/ || true) 2>&1 | head -n 25'; else echo 'No live container found on manager for $service'; fi"
done

echo
echo "=========================================================="
echo "Diagnostic check completed."
echo "=========================================================="
