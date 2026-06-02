# Bootstrap

## Prepare Ansible SSH User

Run this only when a host does not already have the operator user with passwordless sudo. `task apc:bootstrap --` uses `SSH_USER` for the initial login and defaults `SSH_USER_AFTER` to `iac`.

```sh
sudo -s

id iac || useradd -s /bin/bash -m iac
echo 'iac ALL=(ALL:ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/iac
chmod 440 /etc/sudoers.d/iac

mkdir -p /home/iac/.ssh
cat /path/to/gitlab-iac.pub | tee /home/iac/.ssh/authorized_keys
chmod 600 /home/iac/.ssh/authorized_keys
chown -R iac:iac /home/iac/.ssh
```

## Run Bootstrap Script

Replace placeholders with the target host and cluster.

```sh
SSH_HOST="<HOST>" \
SSH_PORT="22" \
SSH_PORT_AFTER="55555" \
SSH_USER="root" \
SSH_USER_AFTER="iac" \
task apc:bootstrap -- <realm> <platform> <cluster>
```

## Apply

Use project Taskfile groups for standard operations where available. Use `task apc:migrate -- apply` before `task apc:run --` for a single cluster:

```sh
task apc:migrate -- apply <realm> <platform> <cluster>
task apc:run -- <realm> <platform> <cluster> setup
task apc:run -- <realm> <platform> <cluster> update
```

By convention, dry/check mode is the default. Set `DRY=0` to apply:

```sh
DRY=0 task apc:migrate -- apply <realm> <platform> <cluster>
DRY=0 task apc:run -- <realm> <platform> <cluster> setup
DRY=0 task apc:run -- <realm> <platform> <cluster> update
```
