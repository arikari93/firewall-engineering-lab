#!/bin/bash
# ============================================================
# backup-config.sh — pfSense Configuration Backup Script
# Firewall Engineering Lab | Author: Ari Said
# Version: 1.2 | Updated: 2026-03-01
#
# PURPOSE:
#   Automated pfSense config backup via SSH/SCP.
#   Runs weekly via cron; retains 30 days of backups.
#   Pre-patch manual backup also uses this script.
#
# USAGE:
#   ./backup-config.sh              # Standard weekly backup
#   ./backup-config.sh --pre-patch  # Pre-patch backup (labeled)
#   ./backup-config.sh --verify     # Verify last backup integrity
#
# PREREQUISITES:
#   - SSH key auth configured: ssh-copy-id admin@10.0.99.1
#   - pfSense SSH enabled on Management VLAN only
#   - Backup destination directory exists and is writable
#
# CRON (add to crontab -e):
#   0 2 * * 0 /opt/lab-scripts/backup-config.sh >> /var/log/pfsense-backup.log 2>&1
# ============================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
PFSENSE_HOST="10.0.99.1"
PFSENSE_USER="admin"
SSH_KEY="$HOME/.ssh/lab_ed25519"
BACKUP_DIR="/opt/backups/pfsense"
RETENTION_DAYS=30
LOG_PREFIX="[pfsense-backup]"

# Remote path to pfSense config (FreeBSD)
REMOTE_CONFIG="/cf/conf/config.xml"

# ── Functions ─────────────────────────────────────────────────────────────────
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"
}

check_prerequisites() {
    log "Checking prerequisites..."

    # Test SSH connectivity
    if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes \
         "$PFSENSE_USER@$PFSENSE_HOST" "echo ok" &>/dev/null; then
        log "ERROR: Cannot SSH to pfSense at $PFSENSE_HOST"
        log "Check: SSH enabled on pfSense, key auth configured, MGMT VLAN accessible"
        exit 1
    fi

    # Ensure backup directory exists
    mkdir -p "$BACKUP_DIR"

    log "Prerequisites OK"
}

backup_config() {
    local label="${1:-weekly}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d_%H%M%S')
    local filename="pfsense-config-${timestamp}-${label}.xml"
    local dest="$BACKUP_DIR/$filename"

    log "Starting backup: $filename"

    # SCP the config.xml from pfSense
    scp -i "$SSH_KEY" \
        -o StrictHostKeyChecking=yes \
        "$PFSENSE_USER@$PFSENSE_HOST:$REMOTE_CONFIG" \
        "$dest"

    # Verify file was created and is non-empty
    if [[ ! -s "$dest" ]]; then
        log "ERROR: Backup file is empty or missing: $dest"
        exit 1
    fi

    # Verify it's valid XML
    if ! xmllint --noout "$dest" 2>/dev/null; then
        log "ERROR: Backup file failed XML validation: $dest"
        exit 1
    fi

    local size
    size=$(du -sh "$dest" | cut -f1)
    log "Backup complete: $dest ($size)"

    # Create a symlink to latest backup for easy reference
    ln -sf "$dest" "$BACKUP_DIR/pfsense-config-latest.xml"

    echo "$dest"
}

purge_old_backups() {
    log "Purging backups older than $RETENTION_DAYS days..."
    local count
    count=$(find "$BACKUP_DIR" -name "pfsense-config-*.xml" \
            -not -name "pfsense-config-latest.xml" \
            -mtime +$RETENTION_DAYS | wc -l)

    find "$BACKUP_DIR" -name "pfsense-config-*.xml" \
         -not -name "pfsense-config-latest.xml" \
         -mtime +$RETENTION_DAYS -delete

    log "Purged $count old backup(s)"
}

verify_backup() {
    local latest="$BACKUP_DIR/pfsense-config-latest.xml"

    if [[ ! -f "$latest" ]]; then
        log "ERROR: No latest backup found at $latest"
        exit 1
    fi

    log "Verifying backup: $latest"

    # XML structure check
    if ! xmllint --noout "$latest" 2>/dev/null; then
        log "ERROR: Latest backup is not valid XML"
        exit 1
    fi

    # Check for key pfSense config sections
    for section in "filter" "nat" "vlans" "openvpn"; do
        if ! grep -q "<${section}>" "$latest"; then
            log "WARNING: Config section <${section}> not found in backup"
        fi
    done

    local age_minutes
    age_minutes=$(( ($(date +%s) - $(stat -c %Y "$latest")) / 60 ))
    local size
    size=$(du -sh "$latest" | cut -f1)

    log "Backup verified: $size, ${age_minutes} minutes old"
    log "VERIFY OK: $latest"
}

print_summary() {
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "pfsense-config-*.xml" \
                   -not -name "pfsense-config-latest.xml" | wc -l)

    log "── Backup Summary ──────────────────────────────"
    log "Backup directory: $BACKUP_DIR"
    log "Total backups retained: $backup_count"
    log "Latest: $(readlink $BACKUP_DIR/pfsense-config-latest.xml 2>/dev/null || echo 'none')"
    log "────────────────────────────────────────────────"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    local mode="${1:---weekly}"

    log "=== pfSense Config Backup Started (mode: $mode) ==="

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
