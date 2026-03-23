# Mailcow - Gmail for WebArena-pro 

This repository now includes the mailcow-compatible compose setup and an automatic bootstrap restore step. You no longer need a separate `mailcow-dockerized` checkout, `./generate_config.sh`, or the interactive `backup_and_restore.sh` flow.

The upstream version drift issue is handled here by keeping this repo pinned to a restore-compatible mailcow snapshot and restoring the seeded mailbox backup automatically on first boot.

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

On the first `up`, the one-shot bootstrap services automatically:
- generates local `.env` and `mailcow.conf` files from the tracked `.env.example` template if they are missing
- generates generic local self-signed TLS files used by mailcow when they are missing
- restores the pinned backup snapshot from `MAILCOW_BOOTSTRAP_BACKUP`
- populates the MariaDB, Redis, Postfix, Rspamd, vmail, and crypt volumes before the main services start

`mailcow-local-seed` writes the local repo files as your user, and `mailcow-bootstrap` restores the Docker volumes.

The generated `.env`, `mailcow.conf`, TLS files, backup `mailcow.conf` snapshots, and the Dovecot/Postfix runtime SQL credential files are local-only artifacts and are not meant to be tracked in git.

The old manual `generate_config.sh`, backup selection prompts, and `sudo chown -R "$USER:$USER" .` workaround are no longer part of setup.

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
