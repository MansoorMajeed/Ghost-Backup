# AWS S3 Setup

## 1. Create an S3 Bucket

1. Go to [S3 Console](https://s3.console.aws.amazon.com/s3/buckets)
2. Click **Create bucket**
3. Enter a bucket name (e.g., `my-ghost-backups`)
4. Select your preferred region
5. Keep "Block all public access" enabled
6. Click **Create bucket**

## 2. Create an IAM User

1. Go to [IAM Console](https://console.aws.amazon.com/iam/)
2. Click **Users** → **Create user**
3. Enter a name (e.g., `ghost-backup`)
4. Click **Next**
5. Select **Attach policies directly**
6. Click **Create policy** and use this JSON (replace `your-bucket-name`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    }
  ]
}
```

7. Name the policy (e.g., `ghost-backup-policy`) and create it
8. Back in the user creation, attach this policy
9. Click **Create user**

## 3. Create Access Keys

1. Click on the user you created
2. Go to **Security credentials** tab
3. Click **Create access key**
4. Select **Application running outside AWS**
5. Copy the **Access key ID** and **Secret access key**

## 4. Configure Ghost Backup

Add to your `.env`:

```bash
RESTIC_REPOSITORY=s3:s3.amazonaws.com/your-bucket-name/ghost
RESTIC_PASSWORD=your-encryption-password

AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

### Repository URL Format

```
s3:s3.amazonaws.com/bucket-name/path
```

Examples:
- `s3:s3.amazonaws.com/my-backups/ghost` - US East
- `s3:s3.eu-west-1.amazonaws.com/my-backups/ghost` - EU (Ireland)
- `s3:s3.ap-southeast-1.amazonaws.com/my-backups/ghost` - Asia Pacific

## 5. Test

```bash
docker compose run --rm backup verify
```
