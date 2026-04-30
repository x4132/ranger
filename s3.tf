resource "random_id" "vpn_configs_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "vpn_configs" {
  bucket        = "ranger-vpn-configs-${random_id.vpn_configs_suffix.hex}"
  force_destroy = true

  tags = {
    Name = "ranger_vpn_configs"
  }
}

resource "aws_s3_bucket_public_access_block" "vpn_configs" {
  bucket = aws_s3_bucket.vpn_configs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vpn_configs" {
  bucket = aws_s3_bucket.vpn_configs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "vpn_configs" {
  bucket = aws_s3_bucket.vpn_configs.id

  rule {
    id     = "expire-old-configs"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}
