output "sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "app_log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "web_log_group_name" {
  value = aws_cloudwatch_log_group.web.name
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.this.dashboard_name}"
}

output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.web_cpu_high.alarm_name,
    aws_cloudwatch_metric_alarm.app_cpu_high.alarm_name,
    aws_cloudwatch_metric_alarm.web_cpu_low.alarm_name,
    aws_cloudwatch_metric_alarm.app_cpu_low.alarm_name,
    aws_cloudwatch_metric_alarm.app_memory_high.alarm_name,
    aws_cloudwatch_metric_alarm.alb_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.alb_latency.alarm_name,
    aws_cloudwatch_metric_alarm.web_unhealthy_hosts.alarm_name,
    aws_cloudwatch_metric_alarm.app_unhealthy_hosts.alarm_name,
    aws_cloudwatch_metric_alarm.app_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.rds_cpu_high.alarm_name,
    aws_cloudwatch_metric_alarm.rds_free_storage_low.alarm_name,
    aws_cloudwatch_metric_alarm.rds_connections_high.alarm_name,
  ]
}
