variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "aws_region" {
  type = string
}

variable "environment" {
  type = string
}

# ---------------------------------------------------------------- Network ----
variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "internal_alb_sg_id" {
  type = string
}

variable "web_sg_id" {
  type = string
}

variable "app_sg_id" {
  type = string
}

variable "bastion_sg_id" {
  type = string
}

# ---------------------------------------------------------------- Compute ----
variable "ami_id" {
  description = "Override AMI. Empty = latest Amazon Linux 2023 (x86_64)."
  type        = string
  default     = ""
}

variable "instance_profile_name" {
  type = string
}

variable "web_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_instance_type" {
  type    = string
  default = "t3.small"
}

variable "root_volume_size" {
  description = "Root EBS volume size (GiB). AL2023 AMIs require >= 8."
  type        = number
  default     = 8
}

variable "web_min_size" {
  type    = number
  default = 1
}

variable "web_max_size" {
  type    = number
  default = 3
}

variable "web_desired" {
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

variable "app_desired" {
  type    = number
  default = 1
}

variable "cpu_target_value" {
  description = "Target average CPU % for target-tracking scaling."
  type        = number
  default     = 60
}

variable "app_port" {
  type    = number
  default = 3000
}

# -------------------------------------------------------------- Artifacts ----
variable "artifacts_bucket" {
  type = string
}

variable "static_assets_bucket" {
  type = string
}

variable "app_bundle_key" {
  description = "S3 key of the zipped application bundle."
  type        = string
}

variable "app_bundle_version" {
  description = "Hash of the app bundle; a change rolls the app tier."
  type        = string
}

variable "static_version" {
  description = "Hash of static assets; a change rolls the web tier."
  type        = string
}

# --------------------------------------------------------------- Database ----
variable "db_host" {
  type = string
}

variable "db_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

# ---------------------------------------------------------------- Logging ----
variable "app_log_group_name" {
  type = string
}

variable "web_log_group_name" {
  type = string
}

variable "enable_alb_access_logs" {
  type    = bool
  default = true
}

variable "access_logs_bucket" {
  type = string
}

# ---------------------------------------------------------------- Bastion ----
variable "enable_bastion" {
  type    = bool
  default = false
}

variable "bastion_key_name" {
  type    = string
  default = ""
}
