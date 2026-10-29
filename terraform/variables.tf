###############################################################################
# General
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier used in resource names (lowercase, digits, hyphens)."
  type        = string
  default     = "mtwa"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.project_name))
    error_message = "project_name must be 2-20 chars, start with a letter, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "environment must be 2-10 lowercase alphanumeric characters."
  }
}

variable "extra_tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}

###############################################################################
# Networking
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Exactly two AZs to use. Leave empty to use the first two available AZs in the region."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) == 2
    error_message = "availability_zones must be empty or contain exactly two AZs."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the two public subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the two private subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH into the optional bastion host (e.g. your public IP /32)."
  type        = string
  default     = "203.0.113.10/32"

  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid IPv4 CIDR and must not be 0.0.0.0/0."
  }
}

###############################################################################
# Compute
###############################################################################

variable "web_instance_type" {
  description = "Instance type for the nginx web tier."
  type        = string
  default     = "t3.micro"
}

variable "app_instance_type" {
  description = "Instance type for the Node.js application tier."
  type        = string
  default     = "t3.small"
}

variable "web_min_size" {
  type    = number
  default = 1
}

variable "web_max_size" {
  type    = number
  default = 3
}

variable "web_desired_capacity" {
  type    = number
  default = 1
}

variable "app_min_size" {
  type    = number
  default = 1
}

variable "app_max_size" {
  type    = number
  default = 3
}

variable "app_desired_capacity" {
  type    = number
  default = 1
}

variable "app_port" {
  description = "Port the Node.js application listens on."
  type        = number
  default     = 3000
}

variable "enable_bastion" {
  description = "Create an optional SSH bastion host in a public subnet. SSM Session Manager works without it."
  type        = bool
  default     = false
}

variable "bastion_key_name" {
  description = "Existing EC2 key pair name for the bastion host (required only when enable_bastion = true)."
  type        = string
  default     = ""
}

variable "enable_alb_access_logs" {
  description = "Ship public ALB access logs to the access-logs bucket."
  type        = bool
  default     = true
}

###############################################################################
# Database
###############################################################################

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated RDS storage in GiB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Run RDS in Multi-AZ mode (recommended for prod; doubles RDS cost)."
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for RDS. The password is generated and stored in Secrets Manager."
  type        = string
  default     = "appadmin"
}

variable "db_backup_retention_days" {
  description = "Automated backup retention in days (0 disables backups)."
  type        = number
  default     = 1
}

variable "secret_recovery_window_in_days" {
  description = "Secrets Manager recovery window for the DB secret. 0 = delete immediately (handy for dev re-deploys)."
  type        = number
  default     = 0
}

###############################################################################
# Storage
###############################################################################

variable "s3_force_destroy" {
  description = "Allow Terraform to delete non-empty buckets on destroy (true for dev, false for prod)."
  type        = bool
  default     = true
}

###############################################################################
# Monitoring
###############################################################################

variable "alarm_email" {
  description = "Email subscribed to the alarm SNS topic. Leave empty to skip the subscription."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Retention for CloudWatch log groups."
  type        = number
  default     = 14
}
