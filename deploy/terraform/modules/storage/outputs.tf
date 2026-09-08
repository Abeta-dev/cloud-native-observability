output "tempo_bucket_name" {
  value       = aws_s3_bucket.tempo_traces.id
  description = "Name of the S3 bucket storing OpenTelemetry traces for Tempo"
}

output "tempo_bucket_arn" {
  value       = aws_s3_bucket.tempo_traces.arn
  description = "ARN of the S3 bucket storing OpenTelemetry traces for Tempo"
}

output "loki_bucket_name" {
  value       = aws_s3_bucket.loki_logs.id
  description = "Name of the S3 bucket storing logs for Loki"
}

output "loki_bucket_arn" {
  value       = aws_s3_bucket.loki_logs.arn
  description = "ARN of the S3 bucket storing logs for Loki"
}
