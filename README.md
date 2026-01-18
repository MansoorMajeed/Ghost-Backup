# Ghost Backup

Docker-based backup solution for [Ghost](https://ghost.org) deployments. Uses [Restic](https://restic.net/) for encrypted, deduplicated backups to S3 or Backblaze B2.

> **Note:** Work in progress. Use at your own risk.

## What It Does

- Backs up your Ghost database (MySQL dump) and content files (images, themes, etc.)
- Encrypts everything with AES-256 before uploading
- Deduplicates data - only uploads what changed
- Runs on a schedule (default: 3 AM daily)
- Supports point-in-time recovery from any snapshot

## Quick Start

### 1. Add to your `docker-compose.yml`

```yaml
services:
  # ... your existing ghost and db services ...

  backup:
    image: ghcr.io/mansoormajeed/ghost-backup:main
    restart: unless-stopped
    environment:
      MYSQL_HOST: db
      MYSQL_USER: ghost
      MYSQL_PASSWORD: ${DATABASE_PASSWORD}
      RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}
      RESTIC_PASSWORD: ${RESTIC_PASSWORD}
      # For AWS S3:
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
      # For Backblaze B2 (use instead of AWS creds):
      # B2_ACCOUNT_ID: ${B2_ACCOUNT_ID}
      # B2_ACCOUNT_KEY: ${B2_ACCOUNT_KEY}
    volumes:
      - ./data/ghost:/data/ghost
      - ./data/restore:/restore
    depends_on:
      db:
        condition: service_healthy
    profiles:
      - backup
```

### 2. Add to your `.env`

```bash
# Enable backup
COMPOSE_PROFILES=backup

# Where to store backups
RESTIC_REPOSITORY=s3:s3.amazonaws.com/your-bucket/ghost-backups

# Encryption password (SAVE THIS - you need it to restore)
RESTIC_PASSWORD=your-secure-password

# Cloud credentials
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
```

### 3. Start

```bash
docker compose up -d
```

The backup container validates config on startup and runs backups automatically.

## Cloud Storage Setup

- [AWS S3 Setup Guide](docs/aws-setup.md)
- [Backblaze B2 Setup Guide](docs/b2-setup.md)

## Commands

```bash
# Run a backup now
docker compose run --rm backup backup

# List all snapshots
docker compose run --rm backup snapshots

# Restore from latest backup
docker compose run --rm -it backup restore latest

# Restore specific snapshot
docker compose run --rm -it backup restore abc123

# Check configuration
docker compose run --rm backup verify

# View repository stats
docker compose run --rm backup stats
```

## Restore Process

1. Stop Ghost:
   ```bash
   docker compose stop ghost
   ```

2. Run restore (interactive):
   ```bash
   docker compose run --rm -it backup restore latest
   ```

3. Start Ghost:
   ```bash
   docker compose start ghost
   ```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RESTIC_REPOSITORY` | required | Repository URL |
| `RESTIC_PASSWORD` | required | Encryption password |
| `BACKUP_SCHEDULE` | `0 3 * * *` | Cron schedule |
| `BACKUP_KEEP_DAILY` | `7` | Daily snapshots to keep |
| `BACKUP_KEEP_WEEKLY` | `4` | Weekly snapshots to keep |
| `BACKUP_KEEP_MONTHLY` | `6` | Monthly snapshots to keep |
| `BACKUP_KEEP_YEARLY` | `2` | Yearly snapshots to keep |
| `BACKUP_HEALTHCHECK_URL` | | URL to ping on success/failure |

## What Gets Backed Up

- **Database**: Ghost database (and ActivityPub if present)
- **Content**: images, media, files, themes, settings

## Troubleshooting

```bash
# Check logs
docker compose logs backup

# Remove stale restic lock
docker compose run --rm backup unlock
```

## License

MIT
