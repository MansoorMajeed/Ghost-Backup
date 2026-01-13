# Ghost Backup

A Docker-based backup solution for [Ghost Docker](https://github.com/TryGhost/ghost-docker) deployments. Uses [Restic](https://restic.net/) for encrypted, deduplicated backups to cloud storage.

## Features

- **Encrypted backups** - AES-256 encryption before data leaves your server
- **Deduplication** - Only changed data is uploaded, saving storage costs
- **Point-in-time recovery** - Restore from any backup snapshot
- **Cloud storage support** - S3, Backblaze B2, and S3-compatible providers
- **Automated scheduling** - Cron-based backup scheduling
- **Retention policies** - Automatic cleanup of old backups
- **Validation on startup** - Verifies configuration before running
- **ActivityPub support** - Automatically detects and backs up ActivityPub database

## Quick Start

### 1. Add backup profile to your `.env`

```bash
# Enable backup profile
COMPOSE_PROFILES=backup

# Restic repository (choose one)
RESTIC_REPOSITORY=s3:s3.amazonaws.com/your-bucket/ghost-backups
# RESTIC_REPOSITORY=b2:your-bucket:ghost-backups

# Repository password (use a strong password!)
RESTIC_PASSWORD=your-secure-password-here

# Cloud credentials (for S3)
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key

# Or for Backblaze B2
# B2_ACCOUNT_ID=your-account-id
# B2_ACCOUNT_KEY=your-account-key
```

### 2. Start Ghost with backups

```bash
docker compose up -d
```

The backup container will:
1. Validate all configuration on startup
2. Run scheduled backups (default: 3 AM daily)
3. Apply retention policies automatically

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `RESTIC_REPOSITORY` | Restic repository URL |
| `RESTIC_PASSWORD` | Repository encryption password |

### Cloud Provider Credentials

**AWS S3:**
```bash
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
RESTIC_REPOSITORY=s3:s3.amazonaws.com/bucket/path
```

**Backblaze B2:**
```bash
B2_ACCOUNT_ID=...
B2_ACCOUNT_KEY=...
RESTIC_REPOSITORY=b2:bucket-name:path
```

**S3-compatible (MinIO, Wasabi, etc):**
```bash
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
RESTIC_REPOSITORY=s3:https://s3.wasabisys.com/bucket/path
```

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_SCHEDULE` | `0 3 * * *` | Cron schedule (default: 3 AM daily) |
| `BACKUP_KEEP_DAILY` | `7` | Daily snapshots to keep |
| `BACKUP_KEEP_WEEKLY` | `4` | Weekly snapshots to keep |
| `BACKUP_KEEP_MONTHLY` | `6` | Monthly snapshots to keep |
| `BACKUP_KEEP_YEARLY` | `2` | Yearly snapshots to keep |
| `BACKUP_HEALTHCHECK_URL` | | URL to ping on backup success/failure |

## Commands

### Manual Backup

```bash
docker compose run --rm backup backup
```

### List Snapshots

```bash
docker compose run --rm backup snapshots
```

### Restore a Snapshot

```bash
# Restore latest
docker compose run --rm backup restore latest

# Restore specific snapshot
docker compose run --rm backup restore abc123
```

### Verify Configuration

```bash
docker compose run --rm backup verify
```

### View Repository Stats

```bash
docker compose run --rm backup stats
```

### Remove Stale Locks

```bash
docker compose run --rm backup unlock
```

## What Gets Backed Up

| Data | Description |
|------|-------------|
| Ghost database | Full MySQL dump of the `ghost` database |
| Ghost content | Images, themes, files (`/var/lib/ghost/content`) |
| ActivityPub database | If ActivityPub profile is enabled |

## Restore Process

Restoring is intentionally manual to prevent accidents.

1. **Restore to staging area:**
   ```bash
   docker compose run --rm backup restore latest
   ```

2. **Stop Ghost:**
   ```bash
   docker compose stop ghost
   ```

3. **Import database:**
   ```bash
   docker compose exec -T db mysql -u root -p$DATABASE_ROOT_PASSWORD ghost < ./data/restore/ghost.sql
   ```

4. **Restore content (if needed):**
   ```bash
   rm -rf ./data/ghost/*
   cp -r ./data/restore/content/* ./data/ghost/
   chown -R 1000:1000 ./data/ghost
   ```

5. **Start Ghost:**
   ```bash
   docker compose start ghost
   ```

6. **Clean up:**
   ```bash
   rm -rf ./data/restore
   ```

## Monitoring

### Health Check Integration

Set `BACKUP_HEALTHCHECK_URL` to receive notifications:

```bash
# healthchecks.io
BACKUP_HEALTHCHECK_URL=https://hc-ping.com/your-uuid

# Uptime Kuma
BACKUP_HEALTHCHECK_URL=https://uptime.example.com/api/push/xxx
```

### Logs

```bash
docker compose logs backup
docker compose logs -f backup  # Follow logs
```

## Troubleshooting

### Validation Failed

Check the error message in the logs:

```bash
docker compose logs backup
```

Common issues:
- Missing environment variables
- Database not accessible
- Invalid cloud credentials
- Repository password mismatch

### Backup Failed

```bash
# Check logs
docker compose logs backup

# Run manual backup with output
docker compose run --rm backup backup
```

### Repository Locked

If a backup was interrupted, the repository may be locked:

```bash
docker compose run --rm backup unlock
```

## Security

- All data is encrypted with AES-256 before upload
- Repository password never leaves your server
- Content volume is mounted read-only
- Cloud credentials are only used by the backup container

**Important:** Store your `RESTIC_PASSWORD` securely. If you lose it, your backups cannot be decrypted.

## Development

### Building Locally

```bash
docker build -t ghost-backup .
```

### Running Tests

```bash
# Validate configuration
docker compose run --rm backup verify

# Test backup (dry run not supported, use a test repository)
docker compose run --rm backup backup
```

## License

MIT
