# OpenObserve Deployment Commands

## Deploy Configuration

To upload the `vector.toml` configuration to all VPS nodes, run the following command from the root of the project (or adjust paths accordingly).

Assuming you are in `my-vps-management` directory:

```bash
ansible-playbook -i inventory.ini deploy_openobserve.yml
```

This playbook performs the following:
1.  **Creates Directory**: Ensures `/data/apps/openobserve` exists on the target servers.
2.  **Uploads Config**: Copies the local `vector.toml` to the server.
    *   **Default Behavior**: Skips the upload if `vector.toml` already exists on the server.
    *   **Force Override**: See below.

### Force Override (Delete and Re-upload)

To force the deletion of the existing file and re-upload the latest version, use the `force_update` variable:

```bash
ansible-playbook -i inventory.ini deploy_openobserve.yml -e "force_update=true"
```

## Prerequisites

- Ensure you have SSH access to the nodes defined in `inventory.ini`.
- The local `vector.toml` file must exist in `prod-docker/apps/openobserve/`.
