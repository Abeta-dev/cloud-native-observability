resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# Tempo Distributed Traces S3 Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "tempo_traces" {
  bucket        = "${var.project_name}-tempo-traces-${var.environment}-${random_id.bucket_suffix.hex}"
  force_destroy = var.environment != "prod"

  tags = {
    Name        = "${var.project_name}-tempo-traces"
    Environment = var.environment
    Component   = "Observability-Tracing"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tempo_traces" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    id     = "tempo-trace-retention"
    status = "Enabled"

    filter {}

    expiration {
      days = var.trace_retention_days
    }
  }
}

# -----------------------------------------------------------------------------
# Loki Application & System Logs S3 Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "loki_logs" {
  bucket        = "${var.project_name}-loki-logs-${var.environment}-${random_id.bucket_suffix.hex}"
  force_destroy = var.environment != "prod"

  tags = {
    Name        = "${var.project_name}-loki-logs"
    Environment = var.environment
    Component   = "Observability-Logging"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    id     = "loki-log-retention"
    status = "Enabled"

    filter {}

    transition {
      days          = 15
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.log_retention_days
    }
  }
}
