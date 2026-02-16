# Mailcow - Gmail for WebArena-pro 

Due to sync and how `Mailcow` is implemented, there are a few extra steps to load in our latest environment, populated with user emails and data we used to test our agents on for WebArena-Pro:
### 1) Clone the repositories
- git clone this repository and a specific version of the original mailcow docker repository (bug with restoring with their latest version):
```
git clone https://github.com/JackSong88/webarena-pro-mail-manager.git
git clone --depth 1 --branch 2025-10a https://github.com/mailcow/mailcow-dockerized.git mailcow-2025-10a
```
- Some setups may face a `error: pathspec 'master' did not match any file(s) known to git` error, which can be fixed by:
```
cd mailcow-2025-10a
git checkout -B master 2025-10a
```
### 2) Setup the environment
- Generate important certificate and config template through the script:
```
cd mailcow-2025-10a
bash ./generate_config.sh
```
- When prompted, enter the following options:
  - Hostname: mail.local.test
  - Timezone: Accept default (leave blank) or choose yours
  - Branch: Choose 1 (stable)
  - Errors are okay as long as certificates are generated

- If there are any permission errors, fix through:
```
sudo chown -R "$USER:$USER" .
```
#### 2.1) Load the config and the data
- From our repo, copy the `mailcow.conf` config and `backups/` folder which contains all the domains, user emails, and data from this repository to the empty, newly cloned one.
```
cd <project_root_dir>
cp -r webarena-pro-mail-manager/mailcow.conf mailcow-2025-10a
cp -r webarena-pro-mail-manager/backups mailcow-2025-10a
```

### 3) Compose images and data
- Ensure docker images are present:
```
cd mailcow-2025-10a
docker compose pull
``` 
- Run the helper script to restore from backup:
```bash
bash helper-scripts/backup_and_restore.sh restore all
```
  - When prompted: Enter the full path to the backups folder `<full_project_root_dir_path>/mailcow-2025-10a/backups`
  - Select the latest backup version by date (usually the largest number)
    - Select ` [ 0 ] - all` to load in all data from the backup
    - Enter `Y/y` when prompted

### 4) Run environment
- Start containers if not already running:
```
docker compose up -d
```
- Reach the site at https://mail.local.test or custom domain specified in the config 
  - May have to permit host at `/etc/hosts` or equivalent on user OS, if running locally, server ip typically `127.0.0.1`:
  ```
  sudo sh -c 'echo "127.0.0.1 mail.local.test" >> /etc/hosts'
  ```

### 5) Login in
- Login to a user email using their email and password (all are set to `abc123`)
- Mailboxes/Emails and Mail Domains can be found in the admin menu. To login as admin:
  - Either navigate through the `Log in as admin` button or go to `https://mail.local.test/admin/`
  - Then, for the username and password, enter:
  ```
  Username: admin
  Password: moohoo
  ```
  - Accounts can be found under the top right `E-Mail` tab -> `Configuration` -> `Domains` or `Mailboxes`