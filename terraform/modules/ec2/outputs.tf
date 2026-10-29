output "alb_dns_name" {
  value = aws_lb.public.dns_name
}

output "alb_arn" {
  value = aws_lb.public.arn
}

output "alb_arn_suffix" {
  value = aws_lb.public.arn_suffix
}

output "web_target_group_arn_suffix" {
  value = aws_lb_target_group.web.arn_suffix
}

output "internal_alb_dns_name" {
  value = aws_lb.internal.dns_name
}

output "internal_alb_arn_suffix" {
  value = aws_lb.internal.arn_suffix
}

output "app_target_group_arn_suffix" {
  value = aws_lb_target_group.app.arn_suffix
}

output "web_asg_name" {
  value = aws_autoscaling_group.web.name
}

output "app_asg_name" {
  value = aws_autoscaling_group.app.name
}

output "web_launch_template_id" {
  value = aws_launch_template.web.id
}

output "app_launch_template_id" {
  value = aws_launch_template.app.id
}

output "ami_id" {
  value = local.ami_id
}

output "bastion_public_ip" {
  value = try(aws_instance.bastion[0].public_ip, "")
}
