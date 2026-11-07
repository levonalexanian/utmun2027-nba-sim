# Timestamped SQLite snapshots, written by a systemd timer on the instance (user-data.sh).
resource "aws_s3_bucket" "backups" {
  bucket = "${var.project_name}-backups-${var.aws_account_id}"
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = var.backup_retention_days
    }
  }
}

# The instance may only add snapshots, not read or delete them.
data "aws_iam_policy_document" "backups_write" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.backups.arn}/*"]
  }
}

resource "aws_iam_role_policy" "backups_write" {
  name   = "backups-write"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.backups_write.json
}
