# WIP, DO NOT USE: Ghost Backup


> WARNING! I am vibing with this. Do not use.

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

The `RESTIC_REPOSITORY` URL includes the bucket and subdirectory path. Use subdirectories to organize multiple sites or separate backups.

**AWS S3:**
```bash
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...

# Format: s3:s3.amazonaws.com/bucket-name/path/to/backups
RESTIC_REPOSITORY=s3:s3.amazonaws.com/my-backups/ghost-production

# Examples:
# s3:s3.amazonaws.com/company-backups/ghost/prod     # Production site
# s3:s3.amazonaws.com/company-backups/ghost/staging  # Staging site
# s3:s3.eu-west-1.amazonaws.com/bucket/ghost         # EU region
```

**Backblaze B2:**
```bash
B2_ACCOUNT_ID=...
B2_ACCOUNT_KEY=...

# Format: b2:bucket-name:path/in/bucket
RESTIC_REPOSITORY=b2:my-backups:ghost

# More examples (pick ONE, path organizes backups within the bucket):
# b2:my-backups:ghost                    # Simple, single site
# b2:my-backups:sites/ghost/prod         # Organized for multiple sites/environments
# b2:my-backups:sites/ghost/staging
```

To get your B2 credentials:
1. Log in to [Backblaze B2](https://secure.backblaze.com/b2_buckets.htm)
2. Go to **Application Keys** in the left sidebar
3. Click **Add a New Application Key**
4. Set the key name (e.g., "ghost-backup") and select your bucket
5. Copy the `keyID` → `B2_ACCOUNT_ID` and `applicationKey` → `B2_ACCOUNT_KEY`

> **Note:** The application key is only shown once. Save it securely.

**S3-compatible (MinIO, Wasabi, Cloudflare R2, etc):**
```bash
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...

# Format: s3:https://endpoint/bucket/path
RESTIC_REPOSITORY=s3:https://s3.wasabisys.com/my-bucket/ghost

# Examples:
# s3:https://s3.us-west-1.wasabisys.com/backups/ghost    # Wasabi
# s3:https://minio.example.com/backups/ghost              # Self-hosted MinIO
# s3:https://<account>.r2.cloudflarestorage.com/bucket/ghost  # Cloudflare R2
```

**Local path (for testing or NAS):**
```bash
# Mount a volume and use local path
RESTIC_REPOSITORY=/backups/ghost
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

Each backup captures a complete snapshot of your Ghost site:

### Database (MySQL dump)

| Database | Contents |
|----------|----------|
| `ghost` | Posts, pages, tags, users, settings, members, subscriptions, newsletters, email batches, API keys, integrations, webhooks |
| `activitypub` | Followers, following, activities, actors (only if ActivityPub profile is enabled) |

The database is dumped using `mysqldump --single-transaction` which creates a consistent snapshot without locking tables or interrupting your site.

### Content Directory

| Path | Contents |
|------|----------|
| `images/` | All uploaded images (post images, logos, icons, member avatars) |
| `media/` | Uploaded video and audio files |
| `files/` | File attachments (PDFs, documents, etc.) |
| `themes/` | Installed themes (including customizations) |
| `data/` | Redirects configuration (`redirects.json`) |
| `settings/` | Routes configuration (`routes.yaml`) |
| `public/` | Custom static files |

### What is NOT Backed Up

- Ghost application code (pulled from Docker image)
- MySQL data files (we dump the database instead for portability)
- Caddy certificates (auto-regenerated by Let's Encrypt)
- Node modules and system files

## How Backup Works

```
┌─────────────────────────────────────────────────────────────────┐
│  BACKUP PROCESS                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. LOCAL STAGING (requires temporary disk space)               │
│     ├── mysqldump ghost → /tmp/backup-staging/ghost.sql        │
│     └── mysqldump activitypub → /tmp/backup-staging/ap.sql     │
│                                                                 │
│  2. RESTIC BACKUP (reads content directory + staging)           │
│     ├── Splits files into content-addressed chunks             │
│     ├── Compares chunks against existing repository            │
│     ├── Encrypts only NEW chunks with AES-256                  │
│     └── Uploads only NEW chunks to cloud storage               │
│                                                                 │
│  3. CLEANUP                                                     │
│     └── Removes /tmp/backup-staging                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Deduplication happens at upload time**, not locally. Restic compares chunks against what's already in the cloud repository, so only changed data is uploaded.

## Disk Space Requirements

The backup container needs temporary local disk space for the MySQL dump:

| Component | Space Required |
|-----------|----------------|
| MySQL dump | ~1-2x your database size (uncompressed SQL) |
| Staging overhead | ~100 MB |

**Example:** If your Ghost database is 500 MB, ensure at least 1 GB free in the container's `/tmp` directory.

The content directory is read directly (not copied), so it doesn't require additional space.

### Checking Available Space

The backup validates disk space on startup. If space is insufficient, you'll see an error in the logs:

```bash
docker compose logs backup
```

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
