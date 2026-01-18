# Ghost Docker Integration

This document describes the changes needed in [ghost-docker](https://github.com/TryGhost/ghost-docker) to integrate the backup service.

## Changes to `compose.yml`

Add this service at the end of the services section (before `volumes:`):

```yaml
  backup:
    image: ghcr.io/mansoormajeed/ghost-backup:main
    restart: unless-stopped
    environment:
      # Database connection (reuses existing vars)
      MYSQL_HOST: db
      MYSQL_USER: ${DATABASE_USER:-ghost}
      MYSQL_PASSWORD: ${DATABASE_PASSWORD}
      MYSQL_DATABASE: ghost
      # Restic configuration
      RESTIC_REPOSITORY: ${RESTIC_REPOSITORY:-}
      RESTIC_PASSWORD: ${RESTIC_PASSWORD:-}
      # Cloud credentials (S3)
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:-}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:-}
      # Cloud credentials (B2)
      B2_ACCOUNT_ID: ${B2_ACCOUNT_ID:-}
      B2_ACCOUNT_KEY: ${B2_ACCOUNT_KEY:-}
      # Backup settings
      BACKUP_SCHEDULE: ${BACKUP_SCHEDULE:-0 3 * * *}
      BACKUP_KEEP_DAILY: ${BACKUP_KEEP_DAILY:-7}
      BACKUP_KEEP_WEEKLY: ${BACKUP_KEEP_WEEKLY:-4}
      BACKUP_KEEP_MONTHLY: ${BACKUP_KEEP_MONTHLY:-6}
      BACKUP_KEEP_YEARLY: ${BACKUP_KEEP_YEARLY:-2}
      BACKUP_HEALTHCHECK_URL: ${BACKUP_HEALTHCHECK_URL:-}
    volumes:
      - ${UPLOAD_LOCATION:-./data/ghost}:/data/ghost:ro
      - ./data/restore:/restore
    depends_on:
      db:
        condition: service_healthy
    profiles:
      - backup
    networks:
      - ghost_network
```

## Changes to `.env.example`

Add this section at the end of the file:

```bash
# ═══════════════════════════════════════════════════════════════════
# Backup Configuration
# ═══════════════════════════════════════════════════════════════════
# Enable backups by adding 'backup' to COMPOSE_PROFILES
# Example: COMPOSE_PROFILES=backup or COMPOSE_PROFILES=backup,analytics

# Restic repository URL (required for backups)
# The path after the bucket is the subdirectory for your backups
#
# AWS S3:
#   RESTIC_REPOSITORY=s3:s3.amazonaws.com/bucket-name/ghost-backups
#   RESTIC_REPOSITORY=s3:s3.eu-west-1.amazonaws.com/bucket/prod/ghost
#
# Backblaze B2 (format: b2:bucket-name:path/in/bucket):
#   RESTIC_REPOSITORY=b2:my-backups:ghost              # simple
#   RESTIC_REPOSITORY=b2:my-backups:sites/ghost/prod   # organized for multiple sites
#
# S3-compatible (Wasabi, MinIO, Cloudflare R2):
#   RESTIC_REPOSITORY=s3:https://s3.wasabisys.com/bucket/ghost
#   RESTIC_REPOSITORY=s3:https://minio.example.com/backups/ghost
#
# RESTIC_REPOSITORY=

# Repository encryption password (required, use a strong password!)
# WARNING: If you lose this password, your backups cannot be recovered!
# RESTIC_PASSWORD=

# AWS S3 credentials
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=

# Backblaze B2 credentials (use instead of AWS credentials for B2)
# B2_ACCOUNT_ID=
# B2_ACCOUNT_KEY=

# Backup schedule (cron format, default: 3 AM daily)
# BACKUP_SCHEDULE=0 3 * * *

# Retention policy (how many snapshots to keep)
# BACKUP_KEEP_DAILY=7
# BACKUP_KEEP_WEEKLY=4
# BACKUP_KEEP_MONTHLY=6
# BACKUP_KEEP_YEARLY=2

# Health check URL (optional, pinged on backup success/failure)
# Supports healthchecks.io, Uptime Kuma, or any URL that accepts GET requests
# BACKUP_HEALTHCHECK_URL=https://hc-ping.com/your-uuid
```

## Changes to `CLAUDE.md`

Add this to the "Common Commands" section:

```bash
# Backup operations (requires backup profile)
docker compose run --rm backup backup      # Manual backup
docker compose run --rm backup snapshots   # List snapshots
docker compose run --rm backup restore latest  # Restore latest snapshot
docker compose run --rm backup verify      # Check configuration
```

## New file: `BACKUP.md`

Create a `BACKUP.md` file with usage documentation. You can adapt the content from the ghost-backup repository's README.md.

---

## Full compose.yml diff

```diff
   activitypub-migrate:
     image: ghcr.io/tryghost/activitypub-migrations:1.1.0@sha256:b3ab20f55d66eb79090130ff91b57fe93f8a4254b446c2c7fa4507535f503662
     environment:
       MYSQL_DB: mysql://${DATABASE_USER:-ghost}:${DATABASE_PASSWORD:?DATABASE_PASSWORD environment variable is required}@tcp(db:3306)/activitypub
     networks:
       - ghost_network
     depends_on:
       db:
         condition: service_healthy
     profiles: [activitypub]
     restart: no

+  backup:
+    image: ghcr.io/mansoormajeed/ghost-backup:main
+    restart: unless-stopped
+    environment:
+      MYSQL_HOST: db
+      MYSQL_USER: ${DATABASE_USER:-ghost}
+      MYSQL_PASSWORD: ${DATABASE_PASSWORD}
+      MYSQL_DATABASE: ghost
+      RESTIC_REPOSITORY: ${RESTIC_REPOSITORY:-}
+      RESTIC_PASSWORD: ${RESTIC_PASSWORD:-}
+      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:-}
+      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:-}
+      B2_ACCOUNT_ID: ${B2_ACCOUNT_ID:-}
+      B2_ACCOUNT_KEY: ${B2_ACCOUNT_KEY:-}
+      BACKUP_SCHEDULE: ${BACKUP_SCHEDULE:-0 3 * * *}
+      BACKUP_KEEP_DAILY: ${BACKUP_KEEP_DAILY:-7}
+      BACKUP_KEEP_WEEKLY: ${BACKUP_KEEP_WEEKLY:-4}
+      BACKUP_KEEP_MONTHLY: ${BACKUP_KEEP_MONTHLY:-6}
+      BACKUP_KEEP_YEARLY: ${BACKUP_KEEP_YEARLY:-2}
+      BACKUP_HEALTHCHECK_URL: ${BACKUP_HEALTHCHECK_URL:-}
+    volumes:
+      - ${UPLOAD_LOCATION:-./data/ghost}:/data/ghost:ro
+      - ./data/restore:/restore
+    depends_on:
+      db:
+        condition: service_healthy
+    profiles:
+      - backup
+    networks:
+      - ghost_network
+
 volumes:
   caddy_data:
   caddy_config:
```
