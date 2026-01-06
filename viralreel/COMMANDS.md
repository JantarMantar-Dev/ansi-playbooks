# ViralReel Playbook Commands

## Grant Credit Playbook

This playbook identifies the node running the `viralreel-appapi` service and executes the credit granting script on that node.

### Usage

Run the following command from the root of the `vps-deploy` project:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini viralreel/grant_credit.yml -e "email=<USER_EMAIL> amount=<AMOUNT>"
```

### Example

To grant **100** credits to **user@example.com**:

```bash
ansible-playbook -i prod-docker/setup-swarm/inventory.ini viralreel/grant_credit.yml -e "email=user@example.com amount=100"
```

### Notes

- The playbook will automatically:
  1.  Find the Docker Swarm node running the `viralreel-appapi` service.
  2.  SSH into that specific node.
  3.  Execute `node dist/scripts/give-credit.js` with your provided arguments.
- **Logging**: The playbook outputs the exact commands run (Docker checks and the credit script) and their output to your console for visibility.
