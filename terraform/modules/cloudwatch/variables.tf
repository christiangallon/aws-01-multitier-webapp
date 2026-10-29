variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "aws_region" {
  type = string
}

variable "alarm_email" {
  description = "Email for SNS alarm notifications (empty = no subscription)."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "custom_metric_namespace" {
  description = "Namespace for metrics derived from application logs."
  type        = string
  default     = "MultiTierApp"
}

# ---------------------------------------------------------------- Targets ----
variable "web_asg_name" {
  type = string
}

variable "app_asg_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "web_target_group_arn_suffix" {
  type = string
}

variable "internal_alb_arn_suffix" {
  type = string
}

variable "app_target_group_arn_suffix" {
  type = string
}

variable "rds_instance_id" {
  type = string
}

# ------------------------------------------------------------- Thresholds ----
variable "cpu_high_threshold" {
  type    = number
  default = 80
}

variable "cpu_low_threshold" {
  type    = number
  default = 10
}

variable "memory_high_threshold" {
  type    = number
  default = 85
}

variable "alb_5xx_threshold" {
  type    = number
  default = 10
}

variable "app_5xx_threshold" {
  type    = number
  default = 10
}

variable "alb_latency_threshold" {
  description = "Average TargetResponseTime threshold in seconds."
  type        = number
  default     = 1
}

variable "rds_free_storage_threshold_gb" {
  type    = number
  default = 2
}

variable "rds_connections_threshold" {
  type    = number
  default = 50
}
