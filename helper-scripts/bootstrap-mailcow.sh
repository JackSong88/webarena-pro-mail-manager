#!/usr/bin/env bash

set -euo pipefail

BACKUP_ROOT="/backups"
STATE_DIR="/bootstrap/state"
REPO_DIR="/workspace/repo"
CONFIG_TEMPLATE="${REPO_DIR}/.env.example"
RUNTIME_ENV_FILE="${REPO_DIR}/.env"
CONFIG_FILE="${REPO_DIR}/mailcow.conf"
ASSETS_DIR="${REPO_DIR}/data/assets"
WELL_KNOWN_DIR="${REPO_DIR}/data/web/.well-known/acme-challenge"
BOOTSTRAP_MODE="${MAILCOW_BOOTSTRAP_MODE:-full}"
OWNER_UID="${LOCAL_UID:-1000}"
OWNER_GID="${LOCAL_GID:-1000}"

log() {
  echo "[mailcow-bootstrap] $*"
}

copy_template_if_missing() {
  local source_file="${1}"
  local target_file="${2}"
  local label="${3}"

  if [[ -f "${target_file}" ]]; then
    return 0
  fi

  cp "${source_file}" "${target_file}"
  chown "${OWNER_UID}:${OWNER_GID}" "${target_file}" 2>/dev/null || true
  chmod 600 "${target_file}" 2>/dev/null || true
  log "Generated local ${label} from $(basename "${source_file}")."
}

write_file_from_stdin() {
  local target_file="${1}"
  local target_dir
  local tmp_file

  target_dir="$(dirname "${target_file}")"
  if ! mkdir -p "${target_dir}" 2>/dev/null; then
    cat >/dev/null
    log "Skipping ${target_file}; ${target_dir} is not writable in ${BOOTSTRAP_MODE} mode."
    return 0
  fi

  if ! tmp_file="$(mktemp "${target_dir}/.$(basename "${target_file}").tmp.XXXXXX" 2>/dev/null)"; then
    cat >/dev/null
    log "Skipping ${target_file}; ${target_dir} is not writable in ${BOOTSTRAP_MODE} mode."
    return 0
  fi

  cat > "${tmp_file}"
  if ! mv -f "${tmp_file}" "${target_file}" 2>/dev/null; then
    rm -f "${tmp_file}"
    log "Skipping ${target_file}; ${target_dir} is not writable in ${BOOTSTRAP_MODE} mode."
    return 0
  fi
  chown "${OWNER_UID}:${OWNER_GID}" "${target_file}" 2>/dev/null || true
}

ensure_env_symlink() {
  ln -sfn mailcow.conf "${REPO_DIR}/.env"
  chown -h "${OWNER_UID}:${OWNER_GID}" "${REPO_DIR}/.env" 2>/dev/null || true
}

fix_generated_file_ownership() {
  chown "${OWNER_UID}:${OWNER_GID}" "${CONFIG_FILE}" 2>/dev/null || true
  chown -h "${OWNER_UID}:${OWNER_GID}" "${REPO_DIR}/.env" 2>/dev/null || true
  chown "${OWNER_UID}:${OWNER_GID}" \
    "${ASSETS_DIR}/ssl/cert.pem" \
    "${ASSETS_DIR}/ssl/key.pem" \
    "${ASSETS_DIR}/ssl/dhparams.pem" \
    "${ASSETS_DIR}/ssl-example/cert.pem" \
    "${ASSETS_DIR}/ssl-example/key.pem" \
    "${ASSETS_DIR}/ssl-example/dhparams.pem" \
    "${REPO_DIR}/data/web/inc/app_info.inc.php" \
    2>/dev/null || true
}

run_generate_config_auto() {
  ensure_env_symlink

  (
    cd "${REPO_DIR}"
    MAILCOW_AUTO_CONFIG=y \
    MAILCOW_AUTO_OVERWRITE=y \
    MAILCOW_HOSTNAME="${MAILCOW_HOSTNAME:-local.test}" \
    MAILCOW_TZ="${TZ:-America/Toronto}" \
    DOCKER_COMPOSE_VERSION="${DOCKER_COMPOSE_VERSION:-native}" \
    ENABLE_IPV6="${ENABLE_IPV6:-false}" \
    SKIP_CLAMD="${SKIP_CLAMD:-n}" \
    MAILCOW_BRANCH="${MAILCOW_BOOTSTRAP_BRANCH:-main}" \
    bash ./generate_config.sh --dev
  )

  ensure_env_symlink
  fix_generated_file_ownership
}

apply_backup_mailcow_conf() {
  if [[ ! -f "${BACKUP_DIR}/mailcow.conf" ]]; then
    log "Skipping backup config apply: ${BACKUP_DIR}/mailcow.conf is missing."
    return 0
  fi

  cp "${BACKUP_DIR}/mailcow.conf" "${CONFIG_FILE}"
  chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
  chown "${OWNER_UID}:${OWNER_GID}" "${CONFIG_FILE}" 2>/dev/null || true
  ensure_env_symlink
}

run_backup_restore_auto() {
  (
    cd "${REPO_DIR}"
    MAILCOW_BACKUP_LOCATION="${BACKUP_ROOT}" \
    MAILCOW_AUTOMATED_RESTORE=y \
    MAILCOW_RESTORE_POINT="${backup_name}" \
    MAILCOW_RESTORE_DATASET=all \
    MAILCOW_RESTORE_DIRECT=y \
    MAILCOW_DIRECT_TARGET_MYSQL="/bootstrap/mysql" \
    MAILCOW_DIRECT_TARGET_VMAIL="/bootstrap/vmail" \
    MAILCOW_DIRECT_TARGET_CRYPT="/bootstrap/crypt" \
    MAILCOW_DIRECT_TARGET_POSTFIX="/bootstrap/postfix" \
    MAILCOW_DIRECT_TARGET_REDIS="/bootstrap/redis" \
    MAILCOW_DIRECT_TARGET_RSPAMD="/bootstrap/rspamd" \
    bash ./helper-scripts/backup_and_restore.sh restore all
  )
}

ensure_local_config() {
  local config_source="${CONFIG_TEMPLATE}"

  if [[ ! -f "${CONFIG_TEMPLATE}" ]]; then
    log "Missing ${CONFIG_TEMPLATE}; cannot render local mailcow.conf."
    exit 1
  fi

  copy_template_if_missing "${CONFIG_TEMPLATE}" "${RUNTIME_ENV_FILE}" ".env"

  if [[ -f "${RUNTIME_ENV_FILE}" ]]; then
    config_source="${RUNTIME_ENV_FILE}"
  fi

  copy_template_if_missing "${config_source}" "${CONFIG_FILE}" "mailcow.conf"
}

normalize_arch() {
  case "${1}" in
    x86_64|amd64)
      echo "x86_64"
      ;;
    aarch64|arm64)
      echo "aarch64"
      ;;
    *)
      echo "${1}"
      ;;
  esac
}

resolve_backup_name() {
  local candidate
  local latest=""

  if [[ -n "${MAILCOW_BOOTSTRAP_BACKUP:-}" ]]; then
    echo "${MAILCOW_BOOTSTRAP_BACKUP}"
    return 0
  fi

  for candidate in "${BACKUP_ROOT}"/mailcow-*; do
    [[ -d "${candidate}" ]] || continue
    latest="$(basename "${candidate}")"
  done

  echo "${latest}"
}

clear_dir() {
  local target="${1}"

  mkdir -p "${target}"
  find "${target}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

clear_generated_runtime_files() {
  log "Removing generated runtime config so services can rebuild it from the seeded snapshot..."

  rm -f \
    "${REPO_DIR}/data/conf/dovecot/dovecot-master.passwd" \
    "${REPO_DIR}/data/conf/dovecot/dovecot-master.userdb" \
    "${REPO_DIR}/data/conf/dovecot/sogo-sso.conf" \
    "${REPO_DIR}/data/conf/dovecot/sql/"*.conf \
    "${REPO_DIR}/data/conf/phpfpm/sogo-sso/sogo-sso.pass" \
    "${REPO_DIR}/data/conf/postfix/custom_transport.pcre" \
    "${REPO_DIR}/data/conf/postfix/sql/"*.cf \
    "${REPO_DIR}/data/conf/sogo/cron.creds" \
    "${REPO_DIR}/data/conf/sogo/sieve.creds" \
    2>/dev/null || true
}

seed_runtime_templates() {
  mkdir -p \
    "${REPO_DIR}/data/conf/dovecot/auth" \
    "${REPO_DIR}/data/conf/dovecot" \
    "${REPO_DIR}/data/conf/rspamd/override.d"

  write_file_from_stdin "${REPO_DIR}/data/conf/dovecot/auth/passwd-verify.lua" <<'EOF'
function auth_password_verify(request, password)
 if request.domain == nil then
 return dovecot.auth.PASSDB_RESULT_USER_UNKNOWN, "No such user"
 end

 json = require "cjson"
 ltn12 = require "ltn12"
 https = require "ssl.https"
 https.TIMEOUT = 5

 local req = {
 username = request.user,
 password = password,
 real_rip = request.real_rip,
 protocol = {}
 }
 req.protocol[request.service] = true
 local req_json = json.encode(req)
 local res = {}

 local b, c = https.request {
 method = "POST",
 url = "https://nginx:9082",
 source = ltn12.source.string(req_json),
 headers = {
 ["content-type"] = "application/json",
 ["content-length"] = tostring(#req_json)
 },
 sink = ltn12.sink.table(res),
 insecure = true
 }
 local api_response = json.decode(table.concat(res))
 if api_response.success == true then
 return dovecot.auth.PASSDB_RESULT_OK, ""
 end

 return dovecot.auth.PASSDB_RESULT_PASSWORD_MISMATCH, "Failed to authenticate"
end

function auth_passdb_lookup(req)
 return dovecot.auth.PASSDB_RESULT_USER_UNKNOWN, ""
end
EOF

  write_file_from_stdin "${REPO_DIR}/data/conf/rspamd/override.d/worker-proxy.inc" <<'EOF'
bind_socket = "rspamd:9900";
milter = true;
upstream "local" {
  name = "localhost";
  default = true;
  hosts = "rspamd:11333";
}
reject_message = "This message does not meet our delivery requirements";
.include(try=true; priority=30) "$CONFDIR/override.d/worker-proxy.custom.inc"
EOF

  write_file_from_stdin "${REPO_DIR}/data/conf/rspamd/override.d/worker-normal.inc" <<'EOF'
bind_socket = "*:11333";
task_timeout = 25s;
count = 1;
.include(try=true; priority=30) "$CONFDIR/override.d/worker-normal.custom.inc"
EOF

  if [[ ! -f "${REPO_DIR}/data/conf/dovecot/extra.conf" ]]; then
    : > "${REPO_DIR}/data/conf/dovecot/extra.conf"
  fi
}

clear_maildir_indexes() {
  local vmail_dir="/bootstrap/vmail"

  log "Clearing Dovecot index files so restored mailboxes are rebuilt from the backup contents..."
  find "${vmail_dir}" -type f \
    \( \
      -name 'dovecot.index*' -o \
      -name 'dovecot.mailbox.log*' -o \
      -name 'dovecot-uidlist' \
    \) -delete 2>/dev/null || true
}

restore_tar() {
  local archive_name="${1}"
  local target_dir="${2}"
  local label="${3}"

  if [[ ! -f "${BACKUP_DIR}/${archive_name}" ]]; then
    log "Skipping ${label}: ${archive_name} is missing from ${BACKUP_DIR}."
    return 0
  fi

  log "Restoring ${label} from ${archive_name}..."
  clear_dir "${target_dir}"
  tar -xzf "${BACKUP_DIR}/${archive_name}" --numeric-owner --strip-components=1 -C "${target_dir}"
}

seed_tls_files() {
  local ssl_dir="${ASSETS_DIR}/ssl"
  local ssl_example_dir="${ASSETS_DIR}/ssl-example"
  local hostname="${MAILCOW_HOSTNAME:-local.test}"
  local pem_file
  local cert_metadata
  local dhparam_source=""
  local dhparam_bits=""
  local regenerate_dhparams="n"
  local subject
  local regenerate_tls="n"

  mkdir -p "${ssl_dir}" "${ssl_example_dir}" "${WELL_KNOWN_DIR}"

  if [[ -f "${ssl_dir}/cert.pem" ]]; then
    cert_metadata="$(openssl x509 -in "${ssl_dir}/cert.pem" -noout -subject -ext subjectAltName 2>/dev/null || true)"
    subject="${cert_metadata}"
    if [[ "${subject}" == *"C ="* || "${subject}" == *"ST ="* || "${subject}" == *"L ="* || "${subject}" == *"O ="* || "${subject}" == *"OU ="* ]]; then
      regenerate_tls="y"
    elif [[ "${cert_metadata}" != *"CN = ${hostname}"* || "${cert_metadata}" != *"DNS:${hostname}"* ]]; then
      regenerate_tls="y"
    fi
  fi

  if [[ -f "${ssl_example_dir}/dhparams.pem" ]]; then
    dhparam_source="${ssl_example_dir}/dhparams.pem"
  elif [[ -f "${ssl_dir}/dhparams.pem" ]]; then
    dhparam_source="${ssl_dir}/dhparams.pem"
  fi

  if [[ -n "${dhparam_source}" ]]; then
    dhparam_bits="$(
      openssl dhparam -in "${dhparam_source}" -text -noout 2>/dev/null \
        | sed -n 's/.*(\([0-9][0-9]*\) bit).*/\1/p' \
        | head -n 1
    )"
    if [[ -z "${dhparam_bits}" || "${dhparam_bits}" -lt 2048 ]]; then
      regenerate_dhparams="y"
    fi
  fi

  if [[ "${regenerate_tls}" == "y" || ! -f "${ssl_example_dir}/cert.pem" || ! -f "${ssl_example_dir}/key.pem" ]]; then
    log "Generating generic local self-signed TLS certificate..."
    openssl req -x509 -newkey rsa:2048 \
      -keyout "${ssl_example_dir}/key.pem" \
      -out "${ssl_example_dir}/cert.pem" \
      -days 3650 \
      -sha256 \
      -nodes \
      -subj "/CN=${hostname}" \
      -addext "subjectAltName=DNS:${hostname},DNS:localhost,IP:127.0.0.1" \
      >/dev/null 2>&1
  fi

  if [[ "${regenerate_tls}" == "y" || "${regenerate_dhparams}" == "y" || ! -f "${ssl_example_dir}/dhparams.pem" ]]; then
    log "Generating local DH params..."
    openssl dhparam -out "${ssl_example_dir}/dhparams.pem" 2048 >/dev/null 2>&1
  fi

  if [[ "${regenerate_tls}" == "y" ]]; then
    rm -f "${ssl_dir}/cert.pem" "${ssl_dir}/key.pem" "${ssl_dir}/dhparams.pem"
  elif [[ "${regenerate_dhparams}" == "y" ]]; then
    rm -f "${ssl_dir}/dhparams.pem"
  fi

  for pem_file in cert.pem key.pem dhparams.pem; do
    if [[ -f "${ssl_dir}/${pem_file}" && ! -f "${ssl_example_dir}/${pem_file}" ]]; then
      cp "${ssl_dir}/${pem_file}" "${ssl_example_dir}/${pem_file}"
    fi

    if [[ -f "${ssl_example_dir}/${pem_file}" && ! -f "${ssl_dir}/${pem_file}" ]]; then
      cp "${ssl_example_dir}/${pem_file}" "${ssl_dir}/${pem_file}"
    fi
  done

  chmod 644 "${ssl_dir}/cert.pem" "${ssl_dir}/dhparams.pem" "${ssl_example_dir}/cert.pem" "${ssl_example_dir}/dhparams.pem" 2>/dev/null || true
  chmod 600 "${ssl_dir}/key.pem" "${ssl_example_dir}/key.pem" 2>/dev/null || true
}

case "${BOOTSTRAP_MODE}" in
  local-seed)
    run_generate_config_auto
    seed_tls_files
    seed_runtime_templates
    log "Local repo seed completed."
    exit 0
    ;;
  restore|full)
    ;;
  *)
    log "Unknown MAILCOW_BOOTSTRAP_MODE=${BOOTSTRAP_MODE}."
    exit 1
    ;;
esac

backup_name="$(resolve_backup_name)"
BACKUP_DIR="${BACKUP_ROOT}/${backup_name}"
MARKER_FILE="${STATE_DIR}/${backup_name}.restored"

if [[ -z "${backup_name}" || ! -d "${BACKUP_DIR}" ]]; then
  log "Could not find the backup snapshot to restore. Checked ${BACKUP_DIR}."
  exit 1
fi

mkdir -p "${STATE_DIR}"

if [[ "${BOOTSTRAP_MODE}" == "full" ]]; then
  run_generate_config_auto
  seed_tls_files
  seed_runtime_templates
fi

if [[ "${MAILCOW_BOOTSTRAP_FORCE:-n}" != "y" && -f "${MARKER_FILE}" ]]; then
  log "Bootstrap already completed for ${backup_name}, skipping restore."
  exit 0
fi

apply_backup_mailcow_conf
run_backup_restore_auto
clear_maildir_indexes

clear_generated_runtime_files
seed_runtime_templates
fix_generated_file_ownership

find "${STATE_DIR}" -mindepth 1 -maxdepth 1 -type f -name '*.restored' -delete
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKER_FILE}"
log "Bootstrap restore completed using ${backup_name}."
