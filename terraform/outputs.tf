output "app_url" {
  description = "Public URL of the application (via the internet-facing ALB)."
  value       = "http://${module.ec2.alb_dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the public ALB."
  value       = module.ec2.alb_dns_name
}

output "internal_alb_dns_name" {
  description = "DNS name of the internal ALB in front of the app tier."
  value       = module.ec2.internal_alb_dns_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "web_asg_name" {
  value = module.ec2.web_asg_name
}

output "app_asg_name" {
  value = module.ec2.app_asg_name
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host (empty when disabled)."
  value       = module.ec2.bastion_public_ip
}

output "rds_endpoint" {
  description = "RDS endpoint (host:port)."
  value       = module.rds.db_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding the DB credentials (username/password/host/port/dbname)."
  value       = module.rds.db_secret_arn
}

output "artifacts_bucket" {
  value = module.s3.artifacts_bucket_id
}

output "static_assets_bucket" {
  value = module.s3.static_assets_bucket_id
}

output "access_logs_bucket" {
  value = module.s3.access_logs_bucket_id
}

output "app_bundle_key" {
  value = aws_s3_object.app_bundle.key
}

output "sns_topic_arn" {
  description = "SNS topic receiving CloudWatch alarm notifications."
  value       = module.cloudwatch.sns_topic_arn
}

output "app_log_group" {
  value = module.cloudwatch.app_log_group_name
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL."
  value       = module.cloudwatch.dashboard_url
}

output "aws_region" {
  value = var.aws_region
}

output "environment" {
  value = var.environment
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}
