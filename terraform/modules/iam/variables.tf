variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "artifacts_bucket_arn" {
  description = "ARN of the app-artifacts bucket (read access)."
  type        = string
}

variable "static_assets_bucket_arn" {
  description = "ARN of the static-assets bucket (read access)."
  type        = string
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials."
  type        = string
}
