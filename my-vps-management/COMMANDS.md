# Directory Management Commands

This playbook creates directories from a predefined list. It skips directories that already exist.

## Run with default directories
```bash
ansible-playbook -i inventory.ini create_directories.yml
```

## Run with custom directories
You can override the `dirs` variable from the command line:
```bash
ansible-playbook -i inventory.ini create_directories.yml -e '{"dirs": ["/path/one", "/path/two"]}'
```

## Dry Run (Verify without changes)
```bash
ansible-playbook -i inventory.ini create_directories.yml --check
```
