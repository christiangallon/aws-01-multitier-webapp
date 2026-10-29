output "artifacts_bucket_id" {
  value = aws_s3_bucket.this["artifacts"].id
}

output "artifacts_bucket_arn" {
  value = aws_s3_bucket.this["artifacts"].arn
}

output "static_assets_bucket_id" {
  value = aws_s3_bucket.this["static_assets"].id
}

output "static_assets_bucket_arn" {
  value = aws_s3_bucket.this["static_assets"].arn
}

# Referencing the bucket policy guarantees log delivery is authorised before
# consumers (e.g. the ALB access-log config) use the bucket.
output "access_logs_bucket_id" {
  value = aws_s3_bucket_policy.access_logs.bucket
}

output "access_logs_bucket_arn" {
  value = aws_s3_bucket.this["access_logs"].arn
}
