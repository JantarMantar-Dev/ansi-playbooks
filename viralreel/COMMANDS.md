# ViralReel Playbook Commands

This playbook manages various tasks for the ViralReel application, such as granting credits and seeding the database. It automatically identifies the Swarm node running the `viralreel-appapi` service and executes the requested command inside the container.

## Usage

Run the following command from the root of the `vps-deploy` project:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini viralreel/viralreel_tasks.yml -e "action=<ACTION> [options]"
```

### Available Actions

| Action | Description | Options |
| :--- | :--- | :--- |
| `credit` | (Default) Grants credits to a user | `email=<USER_EMAIL> amount=<AMOUNT>` |
| `seed_plans` | Seeds the plans database | None |
| `seed_voices` | Seeds the voices database | None |
| `seed_subtitles` | Seeds the subtitles database | None |
| `seed_all` | Runs all three seeding commands | None |

---

## Examples

### 1. Grant Credit
To grant **100** credits to **user@example.com**:
```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini viralreel/viralreel_tasks.yml -e "action=credit email=user@example.com amount=100"
```

### 2. Seed Plans
```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini viralreel/viralreel_tasks.yml -e "action=seed_plans"
```

### 3. Seed All (Plans, Voices, Subtitles)
```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini viralreel/viralreel_tasks.yml -e "action=seed_all"
```

---

## Notes

- **Auto-Discovery**: The playbook finds the specific Docker Swarm node hosting the `viralreel-appapi` service and executes commands there.
- **Logging**: All commands and their outputs are printed to the console for easy verification.
