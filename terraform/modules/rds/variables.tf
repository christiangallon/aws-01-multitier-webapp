variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group (must span 2 AZs)."
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group attached to the RDS instance."
  type        = string
}

variable "engine_version" {
  description = "MySQL engine version. A major version (8.0) lets RDS pick the default minor."
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling in GiB (0 disables autoscaling)."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Enable Multi-AZ standby."
  type        = bool
  default     = false
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "backup_retention_period" {
  type    = number
  default = 1
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "skip_final_snapshot" {
  type    = bool
  default = true
}

variable "secret_recovery_window_in_days" {
  description = "0 deletes the secret immediately on destroy; 7-30 keeps it recoverable."
  type        = number
  default     = 0
}
