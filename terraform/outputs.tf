output "web_url" { value = "http://${aws_instance.web.public_ip}" }
output "db_endpoint" { value = aws_db_instance.mysql.address }
output "s3_bucket" { value = aws_s3_bucket.assets.bucket }
output "cloudwatch_alarm" { value = aws_cloudwatch_metric_alarm.cpu.alarm_name }
