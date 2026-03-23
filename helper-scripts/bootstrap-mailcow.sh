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
  chown 1000:1000 "${target_file}" 2>/dev/null || true
  chmod 600 "${target_file}" 2>/dev/null || true
  log "Generated local ${label} from $(basename "${source_file}")."
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
  local hostname="${MAILCOW_HOSTNAME:-mail.local.test}"
  local pem_file
  local subject
  local regenerate_tls="n"

  mkdir -p "${ssl_dir}" "${ssl_example_dir}" "${WELL_KNOWN_DIR}"

  if [[ -f "${ssl_dir}/cert.pem" ]]; then
    subject="$(openssl x509 -in "${ssl_dir}/cert.pem" -noout -subject 2>/dev/null || true)"
    if [[ "${subject}" == *"C ="* || "${subject}" == *"ST ="* || "${subject}" == *"L ="* || "${subject}" == *"O ="* || "${subject}" == *"OU ="* ]]; then
      regenerate_tls="y"
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

  if [[ "${regenerate_tls}" == "y" || ! -f "${ssl_example_dir}/dhparams.pem" ]]; then
    log "Generating local DH params..."
    openssl dhparam -out "${ssl_example_dir}/dhparams.pem" 1024 >/dev/null 2>&1
  fi

  if [[ "${regenerate_tls}" == "y" ]]; then
    rm -f "${ssl_dir}/cert.pem" "${ssl_dir}/key.pem" "${ssl_dir}/dhparams.pem"
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
    ensure_local_config
    seed_tls_files
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
  ensure_local_config
  seed_tls_files
fi

if [[ "${MAILCOW_BOOTSTRAP_FORCE:-n}" != "y" && -f "${MARKER_FILE}" ]]; then
  log "Bootstrap already completed for ${backup_name}, skipping restore."
  exit 0
fi

restore_tar "backup_mariadb.tar.gz" "/bootstrap/mysql" "MariaDB"
restore_tar "backup_vmail.tar.gz" "/bootstrap/vmail" "mail data"
restore_tar "backup_crypt.tar.gz" "/bootstrap/crypt" "mail encryption keys"
restore_tar "backup_postfix.tar.gz" "/bootstrap/postfix" "Postfix spool"
restore_tar "backup_redis.tar.gz" "/bootstrap/redis" "Redis data"

backup_arch=""
if [[ -f "${BACKUP_DIR}/.x86_64" || -f "${BACKUP_DIR}/.amd64" ]]; then
  backup_arch="x86_64"
elif [[ -f "${BACKUP_DIR}/.aarch64" || -f "${BACKUP_DIR}/.arm64" ]]; then
  backup_arch="aarch64"
fi

if [[ -n "${backup_arch}" && "$(normalize_arch "$(uname -m)")" != "${backup_arch}" ]]; then
  log "Skipping Rspamd restore because the backup expects ${backup_arch} but the host is $(normalize_arch "$(uname -m)")."
  clear_dir "/bootstrap/rspamd"
else
  restore_tar "backup_rspamd.tar.gz" "/bootstrap/rspamd" "Rspamd data"
fi

find "${STATE_DIR}" -mindepth 1 -maxdepth 1 -type f -name '*.restored' -delete
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKER_FILE}"
log "Bootstrap restore completed using ${backup_name}."
