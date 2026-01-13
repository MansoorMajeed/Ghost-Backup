#!/bin/bash
set -euo pipefail

# Ghost Backup - Validation Script
# Verifies all dependencies and configuration before backup operations

readonly CONTENT_DIR="/data/ghost"
readonly MYSQL_HOST="${MYSQL_HOST:-db}"
readonly MYSQL_PORT="${MYSQL_PORT:-3306}"
readonly MYSQL_USER="${MYSQL_USER:-ghost}"
readonly MYSQL_DATABASE="${MYSQL_DATABASE:-ghost}"

# Track validation state
VALIDATION_ERRORS=()

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK] $*"
}

add_error() {
    VALIDATION_ERRORS+=("$1")
    log_error "$1"
}

# Check required environment variables
check_environment() {
    log "Checking environment variables..."

    local required_vars=(
        "RESTIC_REPOSITORY"
        "RESTIC_PASSWORD"
        "MYSQL_PASSWORD"
    )

    local missing=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        add_error "Missing required environment variables: ${missing[*]}"
        return 1
    fi

    log_success "All required environment variables are set"
    return 0
}

# Check database connectivity
check_database() {
    log "Checking database connectivity..."

    # Wait for database with timeout
    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if mysqladmin ping -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent 2>/dev/null; then
            break
        fi

        if [[ $attempt -eq $max_attempts ]]; then
            add_error "Cannot connect to MySQL at $MYSQL_HOST:$MYSQL_PORT after $max_attempts attempts"
            return 1
        fi

        log "Waiting for database... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    log_success "Connected to MySQL at $MYSQL_HOST:$MYSQL_PORT"

    # Check if database exists and is accessible
    if ! mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "USE $MYSQL_DATABASE" 2>/dev/null; then
        add_error "Cannot access database '$MYSQL_DATABASE'. Check user permissions."
        return 1
    fi

    log_success "Database '$MYSQL_DATABASE' is accessible"

    # Verify we can read tables (basic check)
    local table_count
    table_count=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -N -e \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_DATABASE'" 2>/dev/null)

    if [[ -z "$table_count" ]] || [[ "$table_count" -eq 0 ]]; then
        add_error "Database '$MYSQL_DATABASE' appears to be empty. Is Ghost initialized?"
        return 1
    fi

    log_success "Database contains $table_count tables"

    # Check for ActivityPub database if it exists
    if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "USE activitypub" 2>/dev/null; then
        log_success "ActivityPub database detected and accessible"
        export BACKUP_ACTIVITYPUB="true"
    else
        export BACKUP_ACTIVITYPUB="false"
    fi

    return 0
}

# Check content directory
check_content_directory() {
    log "Checking content directory..."

    if [[ ! -d "$CONTENT_DIR" ]]; then
        add_error "Content directory not found at $CONTENT_DIR. Is the volume mounted?"
        return 1
    fi

    if [[ ! -r "$CONTENT_DIR" ]]; then
        add_error "Content directory is not readable at $CONTENT_DIR"
        return 1
    fi

    log_success "Content directory exists and is readable"

    # Check for expected Ghost structure
    local expected_dirs=("images" "themes")
    local found_structure=false

    for dir in "${expected_dirs[@]}"; do
        if [[ -d "$CONTENT_DIR/$dir" ]]; then
            found_structure=true
            break
        fi
    done

    if [[ "$found_structure" == "false" ]]; then
        # This might be a fresh install, just warn
        log "Warning: Expected Ghost directories (images/, themes/) not found. This may be a fresh installation."
    else
        log_success "Ghost content structure verified"
    fi

    # Get content size for info
    local content_size
    content_size=$(du -sh "$CONTENT_DIR" 2>/dev/null | cut -f1)
    log "Content directory size: $content_size"

    return 0
}

# Check available disk space for staging
check_disk_space() {
    log "Checking disk space..."

    # Get database size estimate (data + index size)
    local db_size_bytes
    db_size_bytes=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -N -e \
        "SELECT SUM(data_length + index_length) FROM information_schema.tables WHERE table_schema = '$MYSQL_DATABASE'" 2>/dev/null || echo "0")

    # If we couldn't get size, use a default estimate
    if [[ -z "$db_size_bytes" ]] || [[ "$db_size_bytes" == "NULL" ]]; then
        db_size_bytes=104857600  # 100 MB default
    fi

    # SQL dump is typically 1.5-2x the data size due to SQL syntax overhead
    # Use 2x as safety margin
    local required_bytes=$((db_size_bytes * 2))

    # Add buffer for ActivityPub if present
    if [[ "${BACKUP_ACTIVITYPUB:-false}" == "true" ]]; then
        local ap_size_bytes
        ap_size_bytes=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -N -e \
            "SELECT SUM(data_length + index_length) FROM information_schema.tables WHERE table_schema = 'activitypub'" 2>/dev/null || echo "0")
        if [[ -n "$ap_size_bytes" ]] && [[ "$ap_size_bytes" != "NULL" ]]; then
            required_bytes=$((required_bytes + ap_size_bytes * 2))
        fi
    fi

    # Add 100MB overhead
    required_bytes=$((required_bytes + 104857600))

    # Get available space in /tmp (where staging happens)
    local available_bytes
    available_bytes=$(df -B1 /tmp 2>/dev/null | tail -1 | awk '{print $4}')

    # Convert to human readable
    local required_human available_human
    required_human=$(numfmt --to=iec-i --suffix=B "$required_bytes" 2>/dev/null || echo "${required_bytes} bytes")
    available_human=$(numfmt --to=iec-i --suffix=B "$available_bytes" 2>/dev/null || echo "${available_bytes} bytes")

    log "Estimated space required for MySQL dump: $required_human"
    log "Available space in /tmp: $available_human"

    if [[ "$available_bytes" -lt "$required_bytes" ]]; then
        add_error "Insufficient disk space for backup staging"
        add_error "Required: $required_human, Available: $available_human"
        add_error "Increase container /tmp space or reduce database size"
        return 1
    fi

    log_success "Sufficient disk space available"
    return 0
}

# Check restic repository
check_restic_repository() {
    log "Checking Restic repository..."

    # First check if we can reach the repository
    # restic snapshots will fail if repo doesn't exist but connection works
    # restic init will create it if needed

    if restic snapshots --json 2>/dev/null | head -1 > /dev/null; then
        log_success "Restic repository exists and is accessible"

        # Get repo stats
        local snapshot_count
        snapshot_count=$(restic snapshots --json 2>/dev/null | grep -c '"id"' || echo "0")
        log "Repository contains $snapshot_count snapshot(s)"
        return 0
    fi

    # Check if it's a "repository does not exist" error vs connection error
    local init_output
    if init_output=$(restic init 2>&1); then
        log_success "Initialized new Restic repository"
        return 0
    fi

    # Check for common errors
    if echo "$init_output" | grep -q "already initialized"; then
        # Repo exists but we had a transient error earlier, try again
        if restic snapshots 2>/dev/null; then
            log_success "Restic repository is accessible"
            return 0
        fi
    fi

    if echo "$init_output" | grep -q "wrong password"; then
        add_error "Invalid RESTIC_PASSWORD for repository"
        return 1
    fi

    if echo "$init_output" | grep -q "connection refused\|no such host\|timeout"; then
        add_error "Cannot connect to repository: $RESTIC_REPOSITORY"
        add_error "Check your network connection and repository URL"
        return 1
    fi

    if echo "$init_output" | grep -q "AccessDenied\|InvalidAccessKeyId\|SignatureDoesNotMatch"; then
        add_error "Cloud storage authentication failed. Check your credentials."
        return 1
    fi

    # Generic error
    add_error "Failed to access Restic repository: $init_output"
    return 1
}

# Run all validation checks
main() {
    log "========================================="
    log "Ghost Backup - Validation"
    log "========================================="

    local failed=0

    check_environment || ((failed++))
    check_database || ((failed++))
    check_content_directory || ((failed++))
    check_disk_space || ((failed++))
    check_restic_repository || ((failed++))

    echo ""
    log "========================================="

    if [[ $failed -gt 0 ]]; then
        log_error "Validation FAILED with $failed error(s)"
        echo ""
        log "Errors:"
        for error in "${VALIDATION_ERRORS[@]}"; do
            echo "  - $error"
        done
        echo ""
        exit 1
    fi

    log_success "All validation checks passed"
    log "========================================="
    exit 0
}

main "$@"
