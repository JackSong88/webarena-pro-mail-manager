# Mailcow - Gmail for WebArena-pro 

This repository now automates the original mailcow setup flow on first boot. A fresh `docker compose up -d` will:
- run `./generate_config.sh --dev` automatically to generate the local mailcow config/certs
- replace the generated config with the bundled backup-compatible `mailcow.conf`
- run `helper-scripts/backup_and_restore.sh restore all` automatically against the bundled backup snapshot

That means you no longer need a separate `mailcow-dockerized` checkout or the old manual prompt-driven restore process.

### 1) Clone this repository
```
git clone https://github.com/JackSong88/webarena-pro-mail-manager.git
cd webarena-pro-mail-manager
```

### 2) Add the local hostname
If you are running locally, point `local.test` at `127.0.0.1`:
```
sudo sh -c 'echo "127.0.0.1 local.test" >> /etc/hosts'
```

### 3) Start the stack
```
docker compose up -d
```

On the first `up`, the one-shot bootstrap services automatically replay the old README steps:
- `mailcow-local-seed` runs `generate_config.sh` non-interactively
- the bundled backup `mailcow.conf` is applied
- `mailcow-bootstrap` runs `helper-scripts/backup_and_restore.sh restore all` in automated mode
- MariaDB, Redis, Postfix, Rspamd, vmail, and crypt data are restored before the main services start

The generated `.env` is a symlink to `mailcow.conf`, just like the original manual mailcow setup.

The generated `.env`, `mailcow.conf`, TLS files, backup `mailcow.conf` snapshots, and the Dovecot/Postfix runtime SQL credential files are local-only artifacts and are not meant to be tracked in git.

The old manual `generate_config.sh`, backup selection prompts, and `sudo chown -R "$USER:$USER" .` workaround are no longer needed.

If you want to inspect that bootstrap step:
```
docker compose logs mailcow-bootstrap
```

`mailcow-bootstrap` is expected to exit successfully after it finishes restoring the seeded snapshot.

### 4) Reset back to the seeded mailbox state
To fully reset the environment and repopulate it from the bundled backup data:
```
docker compose down -v
docker compose up -d
```

Because the restore marker lives in a Docker volume, removing volumes with `down -v` causes the next `up` to repopulate the stack automatically.

### 5) Login
- Login to a user email using their email and password (all are set to `abc123`)
- Mailboxes/Emails and Mail Domains can be found in the admin menu. To login as admin:
  - Either navigate through the `Log in as admin` button or go to `https://local.test/admin/`
  - Then, for the username and password, enter:
  ```
  Username: admin
  Password: moohoo
  ```
  - Accounts can be found under the top right `E-Mail` tab -> `Configuration` -> `Domains` or `Mailboxes`
