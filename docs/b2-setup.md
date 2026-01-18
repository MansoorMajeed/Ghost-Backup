# Backblaze B2 Setup

## 1. Create a Bucket

1. Log in to [Backblaze B2](https://secure.backblaze.com/b2_buckets.htm)
2. Click **Create a Bucket**
3. Enter a bucket name (e.g., `my-ghost-backups`)
4. Set **Files in Bucket are** to **Private**
5. Disable **Object Lock** (not needed)
6. Click **Create a Bucket**

## 2. Create an Application Key

1. Go to **Application Keys** in the left sidebar
2. Click **Add a New Application Key**
3. Enter a name (e.g., `ghost-backup`)
4. Select your bucket under **Allow access to Bucket(s)**
5. Leave **Type of Access** as **Read and Write**
6. Click **Create New Key**
7. Copy both values:
   - `keyID` → use as `B2_ACCOUNT_ID`
   - `applicationKey` → use as `B2_ACCOUNT_KEY`

> **Important:** The application key is only shown once. Save it securely.

## 3. Configure Ghost Backup

Add to your `.env`:

```bash
RESTIC_REPOSITORY=b2:your-bucket-name:ghost
RESTIC_PASSWORD=your-encryption-password

B2_ACCOUNT_ID=your-key-id
B2_ACCOUNT_KEY=your-application-key
```

### Repository URL Format

```
b2:bucket-name:path/in/bucket
```

Examples:
- `b2:my-backups:ghost` - Simple
- `b2:my-backups:sites/ghost/prod` - Organized for multiple sites

## 4. Test

```bash
docker compose run --rm backup verify
```

## Pricing

B2 is generally cheaper than S3:
- Storage: $6/TB/month
- Downloads: $0.01/GB (first 1GB free daily)
- Uploads: Free

Check [Backblaze pricing](https://www.backblaze.com/cloud-storage/pricing) for current rates.
