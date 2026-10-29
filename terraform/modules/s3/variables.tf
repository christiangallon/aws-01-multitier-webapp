variable "bucket_prefix" {
  description = "Globally-unique prefix for bucket names; buckets are {prefix}-app-artifacts, {prefix}-static-assets, {prefix}-access-logs."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,45}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 3-46 chars of lowercase letters, digits and hyphens."
  }
}

variable "force_destroy" {
  description = "Delete all objects (including versions) when destroying the buckets."
  type        = bool
  default     = true
}
