output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "web_sg_id" {
  value = aws_security_group.web.id
}

output "internal_alb_sg_id" {
  value = aws_security_group.internal_alb.id
}

output "app_sg_id" {
  value = aws_security_group.app.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}

output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}
