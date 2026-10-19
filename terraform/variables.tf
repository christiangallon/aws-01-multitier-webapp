variable "aws_region" { type = string, default = "us-east-1" }
variable "project" { type = string, default = "aws-01-multitier-webapp" }
variable "instance_type" { type = string, default = "t3.micro" }
variable "db_username" { type = string, default = "appadmin" }
variable "db_password" { type = string, sensitive = true }
variable "alert_email" { type = string, default = "" }
