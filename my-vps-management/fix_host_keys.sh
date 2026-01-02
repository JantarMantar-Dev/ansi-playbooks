#!/bin/bash
# Add host keys to known_hosts to avoid "Host key verification failed"

SERVER_IPS=("23.29.118.41" "104.225.219.149" "104.225.219.171" "104.225.219.150")

for ip in "${SERVER_IPS[@]}"; do
    echo "Scanning $ip..."
    ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null
    ssh-keyscan "$ip" >> ~/.ssh/known_hosts 2>/dev/null
done

echo "Host keys added to ~/.ssh/known_hosts"
