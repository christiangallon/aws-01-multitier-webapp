variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the security groups in."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to the bastion host."
  type        = string
}

variable "app_port" {
  description = "Port the Node.js application listens on."
  type        = number
  default     = 3000
}
