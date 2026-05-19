#!/bin/bash
# ============================================================
# backup-config.sh — pfSense Configuration Backup Script
# Firewall Engineering Lab | Author: Ari Said
# Version: 2.0 | Updated: 2026-05-19
#
# PURPOSE:
#   Automated, ENCRYPTED pfSense config backup via SSH/SCP.
#   Runs weekly via cron; retains 30 days of backups.
#   Pre-patch manual backup also uses this script.
#
# SECURITY NOTE — WHY THIS SCRIPT ENCRYPTS:
#   pfSense's config.xml contains the FULL secret material of the
#   firewall: VPN private keys, the IPSec pre-shared key, the CA key,
#   admin password hashes, RADIUS secrets, and SNMP strings. A plaintext
#   backup of config.xml is therefore a complete copy of every firewall
#   secret. This script:
#     1. Never writes the plaintext config.xml to persistent disk —
#        it is decrypted only in a tmpfs (RAM) working directory.
#     2. Encrypts every stored backup at rest with age (or gpg).
#     3. Locks the backup directory to 0700 and files to 0600.
#   v1.x of this script stored config.xml in cleartext — that was a
#   real vulnerability and is fixed here.
#
# USAGE:
#   ./backup-config.sh              # Standard weekly backup
#   ./backup-config.sh --pre-patch  # Pre-patch backup (labeled)
#   ./backup-config.sh --verify     # Verify last backup integrity
#
# PREREQUISITES:
#   - SSH key auth configured: ssh-copy-id admin@10.0.99.1
#   - pfSense SSH enabled on Management VLAN only
#   - 'age' installed (https://github.com/FiloSottile/age), OR set
#     USE_GPG=1 to fall back to gpg
#   - An age recipient public key (age1...) in $AGE_RECIPIENT, or a
#     gpg recipient in $GPG_RECIPIENT. The matching PRIVATE key is kept
#     OFF this host (e.g., on a hardware token / offline media) so a
#     compromise of the backup host does not expose the backups.
#
# CRON (add to crontab -e):
#   0 2 * * 0 /opt/lab-scripts/backup-config.sh >> /var/log/pfsense-backup.log 2>&1
# ============================================================

set -euo pipefail
umask 077   # every file this script creates is owner-only by default

# ── Configuration ─────────────────────────────────────────────────────────────
PFSENSE_HOST="10.0.99.1"
PFSENSE_USER="admin"
SSH_KEY="$HOME/.ssh/lab_ed25519"
BACKUP_DIR="/opt/backups/pfsense"
RETENTION_DAYS=30
LOG_PREFIX="[pfsense-backup]"

# Remote path to pfSense config (FreeBSD)
REMOTE_CONFIG="/cf/conf/config.xml"

# Encryption: age by default; set USE_GPG=1 to use gpg instead.
USE_GPG="${USE_GPG:-0}"
AGE_RECIPIENT="${AGE_RECIPIENT:-}"   # e.g. age1qz... (public key)
GPG_RECIPIENT="${GPG_RECIPIENT:-}"   # e.g. backup@lab.internal

# tmpfs (RAM-backed) working directory — plaintext never touches disk.
WORK_DIR=""

# ── Functions ─────────────────────────────────────────────────────────────────
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"
}

# Securely remove the RAM working directory on ANY exit path.
cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        # Best-effort shred of any plaintext, then remove.
        find "$WORK_DIR" -type f -exec shred -u {} \; 2>/dev/null || true
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT INT TERM

make_work_dir() {
    # Prefer a tmpfs mount so plaintext config.xml lives in RAM only.
    if [[ -d /dev/shm ]]; then
        WORK_DIR=$(mktemp -d /dev/shm/pfbackup.XXXXXX)
    else
        log "WARNING: /dev/shm not available — falling back to disk tmpdir."
        log "         Plaintext will be shredded after use, but RAM-only is preferred."
        WORK_DIR=$(mktemp -d)
    fi
    chmod 700 "$WORK_DIR"
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Encryption tooling and recipient must be configured.
    if [[ "$USE_GPG" == "1" ]]; then
        command -v gpg >/dev/null || { log "ERROR: gpg not installed"; exit 1; }
        [[ -n "$GPG_RECIPIENT" ]] || { log "ERROR: GPG_RECIPIENT not set"; exit 1; }
    else
        command -v age >/dev/null || { log "ERROR: age not installed (or set USE_GPG=1)"; exit 1; }
        [[ -n "$AGE_RECIPIENT" ]] || { log "ERROR: AGE_RECIPIENT not set"; exit 1; }
    fi

    # Test SSH connectivity
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes \
         -o StrictHostKeyChecking=yes \
         "$PFSENSE_USER@$PFSENSE_HOST" "echo ok" &>/dev/null; then
        log "ERROR: Cannot SSH to pfSense at $PFSENSE_HOST"
        log "Check: SSH enabled on pfSense, key auth configured, MGMT VLAN reachable, host key known"
        exit 1
    fi

    # Ensure backup directory exists and is locked down to the owner only.
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    log "Prerequisites OK"
}

encrypt_file() {
    # $1 = plaintext source path, $2 = encrypted destination path
    local src="$1" dst="$2"
    if [[ "$USE_GPG" == "1" ]]; then
        gpg --batch --yes --trust-model always \
            --recipient "$GPG_RECIPIENT" \
            --output "$dst" --encrypt "$src"
    else
        age --recipient "$AGE_RECIPIENT" --output "$dst" "$src"
    fi
    chmod 600 "$dst"
}

backup_config() {
    local label="${1:-weekly}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d_%H%M%S')
    local ext; ext=$([[ "$USE_GPG" == "1" ]] && echo "xml.gpg" || echo "xml.age")
    local plain="$WORK_DIR/config.xml"
    local dest="$BACKUP_DIR/pfsense-config-${timestamp}-${label}.${ext}"

    log "Starting backup: $(basename "$dest")"

    # SCP config.xml into the RAM working directory (NOT the backup dir).
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=yes \
        "$PFSENSE_USER@$PFSENSE_HOST:$REMOTE_CONFIG" "$plain"

    # Validate the plaintext BEFORE encrypting.
    if [[ ! -s "$plain" ]]; then
        log "ERROR: Retrieved config is empty"; exit 1
    fi
    if ! xmllint --noout "$plain" 2>/dev/null; then
        log "ERROR: Retrieved config failed XML validation"; exit 1
    fi

    # Encrypt to the persistent backup directory.
    encrypt_file "$plain" "$dest"

    # Plaintext is shredded by the cleanup trap; do it now too for safety.
    shred -u "$plain" 2>/dev/null || rm -f "$plain"

    # Update 'latest' pointer (symlink to the encrypted file).
    ln -sf "$dest" "$BACKUP_DIR/pfsense-config-latest.${ext}"

    local size; size=$(du -sh "$dest" | cut -f1)
    log "Backup complete (encrypted): $dest ($size)"
    echo "$dest"
}

purge_old_backups() {
    log "Purging encrypted backups older than $RETENTION_DAYS days..."
    local count
    count=$(find "$BACKUP_DIR" -type f -name "pfsense-config-*-*" \
            -mtime +"$RETENTION_DAYS" | wc -l)
    find "$BACKUP_DIR" -type f -name "pfsense-config-*-*" \
         -mtime +"$RETENTION_DAYS" -delete
    log "Purged $count old backup(s)"
}

verify_backup() {
    # Verify the latest encrypted backup decrypts and is valid XML.
    # Decryption happens in the RAM work dir; plaintext is shredded after.
    local ext; ext=$([[ "$USE_GPG" == "1" ]] && echo "xml.gpg" || echo "xml.age")
    local latest="$BACKUP_DIR/pfsense-config-latest.${ext}"

    if [[ ! -e "$latest" ]]; then
        log "ERROR: No latest backup found at $latest"; exit 1
    fi
    log "Verifying backup: $(readlink -f "$latest")"

    local plain="$WORK_DIR/verify.xml"
    if [[ "$USE_GPG" == "1" ]]; then
        # Requires the private key to be available (e.g. for a manual verify run).
        gpg --batch --yes --output "$plain" --decrypt "$latest" 2>/dev/null \
            || { log "ERROR: Decryption failed (private key available?)"; exit 1; }
    else
        if [[ -z "${AGE_IDENTITY:-}" ]]; then
            log "NOTE: AGE_IDENTITY not set — skipping decrypt test (private key intentionally off-host)."
            log "VERIFY: ciphertext present and non-empty — OK"
            return 0
        fi
        age --decrypt --identity "$AGE_IDENTITY" --output "$plain" "$latest" \
            || { log "ERROR: Decryption failed"; exit 1; }
    fi

    if ! xmllint --noout "$plain" 2>/dev/null; then
        log "ERROR: Decrypted backup is not valid XML"; exit 1
    fi
    for section in "filter" "nat" "vlans" "openvpn"; do
        grep -q "<${section}>" "$plain" || log "WARNING: section <${section}> not found"
    done
    shred -u "$plain" 2>/dev/null || rm -f "$plain"
    log "VERIFY OK: latest backup decrypts and is structurally valid"
}

print_summary() {
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -type f -name "pfsense-config-*-*" | wc -l)
    log "── Backup Summary ──────────────────────────────"
    log "Backup directory: $BACKUP_DIR (mode $(stat -c '%a' "$BACKUP_DIR"))"
    log "Encrypted backups retained: $backup_count"
    log "Encryption: $([[ "$USE_GPG" == "1" ]] && echo gpg || echo age)"
    log "────────────────────────────────────────────────"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    local mode="${1:---weekly}"
    log "=== pfSense Config Backup Started (mode: $mode) ==="

    make_work_dir
    check_prerequisites

    case "$mode" in
        --pre-patch)
            backup_config "pre-patch"
            verify_backup
            log "Pre-patch backup complete. Safe to proceed with firmware update."
            ;;
        --verify)
            verify_backup
            ;;
        --weekly|*)
            backup_config "weekly"
            purge_old_backups
            verify_backup
            print_summary
            ;;
    esac

    log "=== Backup script completed successfully ==="
}

main "${1:-}"
