# Mailcow - Gmail for WebArena-pro 

Due to sync and how `Mailcow` is implemented, there are a few extra steps to load in our latest environment, populated with user emails and data we used to test our agents on for WebArena-Pro:
- git clone the original mailcow docker repository:
```
git clone https://github.com/mailcow/mailcow-dockerized.git
```
- Copy the `mailcow.conf` config and `backups/` folder which contains all the domains, user emails, and data from this repository to the empty, newly cloned one.
- Ensure docker images are present:
```
docker compose pull
``` 
- Run the script to load in the data:
```bash
bash helper-scripts/backup_and_restore.sh restore all
```
  - When prompted: Enter the path to the backups folder `<project_dir>/backups`
- Start containers if not already running:
```
docker compose up -d
```
- Reach the site at https://mail.local.test or custom domain specified in the config 
  - May have to permit host at `/etc/hosts` or equivalent on user OS


