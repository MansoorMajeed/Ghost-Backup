#!/bin/bash
set -euo pipefail

# Ghost Backup - Restore Script
# Restores a snapshot to a staging directory for manual application

readonly RESTORE_DIR="/restore"
readonly SNAPSHOT_ID="${1:-}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

show_snapshots() {
    log "Available snapshots:"
    echo ""
    restic snapshots --tag ghost
    echo ""
    log "Usage: docker compose run --rm backup restore <snapshot-id>"
    log "Use 'latest' for the most recent snapshot"
}

main() {
    if [[ -z "$SNAPSHOT_ID" ]]; then
        show_snapshots
        exit 1
    fi

    log "========================================="
    log "Ghost Backup - Restore"
    log "========================================="

    # Verify snapshot exists
    log "Verifying snapshot: $SNAPSHOT_ID"

    if ! restic snapshots "$SNAPSHOT_ID" --tag ghost 2>/dev/null | grep -q "$SNAPSHOT_ID\|latest"; then
        if [[ "$SNAPSHOT_ID" != "latest" ]]; then
            log_error "Snapshot not found: $SNAPSHOT_ID"
            show_snapshots
            exit 1
        fi
    fi

    # Clean restore directory
    log "Preparing restore directory..."
    rm -rf "${RESTORE_DIR:?}"/*
    mkdir -p "$RESTORE_DIR"

    # Restore snapshot
    log "Restoring snapshot to $RESTORE_DIR..."

    if ! restic restore "$SNAPSHOT_ID" \
        --target "$RESTORE_DIR" \
        --tag ghost; then
        log_error "Restore failed"
        exit 1
    fi

    # Organize restored files
    log "Organizing restored files..."

    # Move SQL dumps to root of restore directory
    if [[ -d "$RESTORE_DIR/tmp/backup-staging" ]]; then
        mv "$RESTORE_DIR/tmp/backup-staging"/*.sql "$RESTORE_DIR/" 2>/dev/null || true
        rm -rf "$RESTORE_DIR/tmp"
    fi

    # Move content to a cleaner location
    if [[ -d "$RESTORE_DIR/data/ghost" ]]; then
        mv "$RESTORE_DIR/data/ghost" "$RESTORE_DIR/content"
        rm -rf "$RESTORE_DIR/data"
    fi

    log "========================================="
    log "Restore Complete"
    log "========================================="
    echo ""
    log "Restored files are in: $RESTORE_DIR"
    echo ""

    # List what was restored
    log "Restored contents:"
    ls -la "$RESTORE_DIR"
    echo ""

    if [[ -f "$RESTORE_DIR/ghost.sql" ]]; then
        local sql_size
        sql_size=$(du -h "$RESTORE_DIR/ghost.sql" | cut -f1)
        log "  - ghost.sql ($sql_size)"
    fi

    if [[ -f "$RESTORE_DIR/activitypub.sql" ]]; then
        local sql_size
        sql_size=$(du -h "$RESTORE_DIR/activitypub.sql" | cut -f1)
        log "  - activitypub.sql ($sql_size)"
    fi

    if [[ -d "$RESTORE_DIR/content" ]]; then
        local content_size
        content_size=$(du -sh "$RESTORE_DIR/content" | cut -f1)
        log "  - content/ ($content_size)"
    fi

    echo ""
    log "========================================="
    log "Next Steps"
    log "========================================="
    echo ""
    cat <<EOF
To apply this restore:

1. Stop Ghost:
   docker compose stop ghost

2. Import the database:
   docker compose exec -T db mysql -u root -p\$DATABASE_ROOT_PASSWORD ghost < ./data/restore/ghost.sql

3. (Optional) If you have ActivityPub:
   docker compose exec -T db mysql -u root -p\$DATABASE_ROOT_PASSWORD activitypub < ./data/restore/activitypub.sql

4. (Optional) Restore content files:
   rm -rf ./data/ghost/*
   cp -r ./data/restore/content/* ./data/ghost/
   chown -R 1000:1000 ./data/ghost

5. Start Ghost:
   docker compose start ghost

6. Clean up restore staging:
   rm -rf ./data/restore

EOF

    log "========================================="
    exit 0
}

main "$@"
