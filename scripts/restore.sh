#!/bin/bash
set -euo pipefail

# Ghost Backup - Restore Script
# Restores a snapshot with interactive database import

readonly RESTORE_DIR="/restore"
readonly SNAPSHOT_ID="${1:-}"
readonly MYSQL_HOST="${MYSQL_HOST:-db}"
readonly MYSQL_PORT="${MYSQL_PORT:-3306}"
readonly MYSQL_USER="${MYSQL_USER:-ghost}"
readonly MYSQL_DATABASE="${MYSQL_DATABASE:-ghost}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK] $*"
}

show_snapshots() {
    log "Available snapshots:"
    echo ""
    restic snapshots --tag ghost
    echo ""
    log "Usage: docker compose run --rm backup restore <snapshot-id>"
    log "Use 'latest' for the most recent snapshot"
}

confirm() {
    local prompt="$1"
    local response
    echo ""
    read -r -p "$prompt [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

warn_about_ghost() {
    echo ""
    echo "========================================="
    echo "IMPORTANT: Stop Ghost Before Restoring"
    echo "========================================="
    echo ""
    echo "For a clean restore, Ghost should be stopped to ensure:"
    echo "  - No writes occur during database import"
    echo "  - Ghost picks up restored data on next start"
    echo ""
    echo "Run this command in another terminal:"
    echo ""
    echo "    docker compose stop ghost"
    echo ""
    echo "If Ghost is already stopped, you can proceed."
    echo ""

    if ! confirm "Continue with database restore?"; then
        log "Restore cancelled"
        exit 1
    fi
}

import_database() {
    local sql_file="$1"
    local database="$2"

    log "Importing $database database..."

    if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$database" < "$sql_file"; then
        log_success "Database '$database' imported successfully"
        return 0
    else
        log_error "Failed to import database '$database'"
        return 1
    fi
}

restore_content() {
    local source="$RESTORE_DIR/content"
    local target="/data/ghost"
    local backup="$RESTORE_DIR/content-backup"

    log "Restoring content files..."

    # Backup existing content (move contents, not the mount point)
    rm -rf "$backup"
    mkdir -p "$backup"

    if ! mv "$target"/* "$target"/.[!.]* "$backup"/ 2>/dev/null; then
        # mv returns error if no dotfiles exist, check if backup has content
        if [[ -z "$(ls -A "$backup" 2>/dev/null)" ]] && [[ -n "$(ls -A "$target" 2>/dev/null)" ]]; then
            log_error "Failed to backup existing content"
            return 1
        fi
    fi

    # Copy restored content
    if ! cp -a "$source"/. "$target"/; then
        log_error "Failed to copy content files, restoring backup..."
        rm -rf "$target"/*
        mv "$backup"/* "$backup"/.[!.]* "$target"/ 2>/dev/null || true
        rm -rf "$backup"
        return 1
    fi

    # Success - remove backup
    rm -rf "$backup"
    log_success "Content files restored"
    return 0
}

extract_snapshot() {
    # Clean restore directory
    log "Preparing restore directory..."
    rm -rf "${RESTORE_DIR:?}"/*
    mkdir -p "$RESTORE_DIR"

    # Restore snapshot
    log "Extracting snapshot to $RESTORE_DIR..."

    if ! restic restore "$SNAPSHOT_ID" \
        --target "$RESTORE_DIR" \
        --tag ghost; then
        log_error "Restore failed"
        return 1
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

    return 0
}

show_restore_summary() {
    echo ""
    log "========================================="
    log "Snapshot Contents"
    log "========================================="
    echo ""

    if [[ -f "$RESTORE_DIR/ghost.sql" ]]; then
        local sql_size
        sql_size=$(du -h "$RESTORE_DIR/ghost.sql" | cut -f1)
        echo "  [1] Ghost database (ghost.sql - $sql_size)"
    fi

    if [[ -f "$RESTORE_DIR/activitypub.sql" ]]; then
        local sql_size
        sql_size=$(du -h "$RESTORE_DIR/activitypub.sql" | cut -f1)
        echo "  [2] ActivityPub database (activitypub.sql - $sql_size)"
    fi

    if [[ -d "$RESTORE_DIR/content" ]]; then
        local content_size
        content_size=$(du -sh "$RESTORE_DIR/content" | cut -f1)
        echo "  [3] Content files (content/ - $content_size)"
    fi
    echo ""
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

    # Extract snapshot
    if ! extract_snapshot; then
        exit 1
    fi

    # Show what's available
    show_restore_summary

    # Check if any database restore is available
    if [[ -f "$RESTORE_DIR/ghost.sql" ]] || [[ -f "$RESTORE_DIR/activitypub.sql" ]]; then
        # Warn user to stop Ghost before database restore
        warn_about_ghost
    fi

    local restore_failed=0

    # Ghost database restore
    if [[ -f "$RESTORE_DIR/ghost.sql" ]]; then
        echo "----------------------------------------"
        echo "GHOST DATABASE RESTORE"
        echo "----------------------------------------"
        echo "This will REPLACE your current Ghost database."
        echo "All existing posts, settings, and members will be overwritten."
        echo ""

        if confirm "Restore Ghost database?"; then
            if ! import_database "$RESTORE_DIR/ghost.sql" "ghost"; then
                ((restore_failed++))
            fi
        else
            log "Skipped Ghost database restore"
        fi
    fi

    # ActivityPub database restore
    if [[ -f "$RESTORE_DIR/activitypub.sql" ]]; then
        echo ""
        echo "----------------------------------------"
        echo "ACTIVITYPUB DATABASE RESTORE"
        echo "----------------------------------------"
        echo "This will REPLACE your current ActivityPub database."
        echo "All followers and federation data will be overwritten."
        echo ""

        if confirm "Restore ActivityPub database?"; then
            if ! import_database "$RESTORE_DIR/activitypub.sql" "activitypub"; then
                ((restore_failed++))
            fi
        else
            log "Skipped ActivityPub database restore"
        fi
    fi

    # Content files restore
    if [[ -d "$RESTORE_DIR/content" ]]; then
        echo ""
        echo "----------------------------------------"
        echo "CONTENT FILES RESTORE"
        echo "----------------------------------------"
        echo "This will REPLACE all content files (images, themes, etc.)."
        echo "Existing content will be backed up temporarily and replaced."
        echo ""

        if confirm "Restore content files?"; then
            if ! restore_content; then
                ((restore_failed++))
            fi
        else
            log "Skipped content restore"
            echo ""
            echo "To restore content files manually later:"
            echo "  cp -a $RESTORE_DIR/content/. /data/ghost/"
            echo ""
        fi
    fi

    # Final summary
    echo ""
    log "========================================="
    if [[ $restore_failed -eq 0 ]]; then
        log_success "Restore completed"
    else
        log_error "Restore completed with $restore_failed error(s)"
    fi
    log "========================================="
    echo ""
    echo "NEXT STEPS:"
    echo ""
    echo "  1. Start (or restart) Ghost to pick up restored data:"
    echo "     docker compose up -d ghost"
    echo ""
    echo "  2. Clean up restore staging when done:"
    echo "     rm -rf ./data/restore"
    echo ""

    exit $restore_failed
}

main "$@"
