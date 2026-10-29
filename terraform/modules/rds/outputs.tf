output "db_instance_id" {
  description = "RDS instance identifier (used for CloudWatch dimensions)."
  value       = aws_db_instance.this.identifier
}

output "db_instance_arn" {
  value = aws_db_instance.this.arn
}

output "db_address" {
  description = "RDS hostname."
  value       = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_endpoint" {
  description = "host:port"
  value       = aws_db_instance.this.endpoint
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_secret_arn" {
  description = "Secrets Manager ARN containing the DB credentials JSON."
  value       = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db.name
}
