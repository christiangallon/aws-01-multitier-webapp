###############################################################################
# Monitoring: SNS topic, log groups, metric filters, alarms and a dashboard.
###############################################################################

locals {
  alarm_actions = [aws_sns_topic.alarms.arn]
}

# ------------------------------------------------------------------ SNS ----
resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
  # Note: CloudWatch cannot publish to topics encrypted with the AWS-managed
  # aws/sns key; use a customer-managed KMS key if encryption is required.
}

data "aws_iam_policy_document" "sns_cloudwatch" {
  statement {
    sid       = "AllowCloudWatchAlarms"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.sns_cloudwatch.json
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ----------------------------------------------------------- Log groups ----
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/app-tier"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.name_prefix}-app-logs"
  }
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/aws/ec2/web-tier"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.name_prefix}-web-logs"
  }
}

# App logs are JSON lines (see app/src/middleware/logger.js); turn 5xx
# responses and error-level entries into custom metrics.
resource "aws_cloudwatch_log_metric_filter" "app_5xx" {
  name           = "${var.name_prefix}-app-5xx"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.type = \"access\" && $.status >= 500 }"

  metric_transformation {
    name          = "App5xxCount"
    namespace     = var.custom_metric_namespace
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.name_prefix}-app-errors"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.level = \"error\" }"

  metric_transformation {
    name          = "AppErrorCount"
    namespace     = var.custom_metric_namespace
    value         = "1"
    default_value = "0"
  }
}

# ------------------------------------------------------------ EC2 / ASG ----
resource "aws_cloudwatch_metric_alarm" "web_cpu_high" {
  alarm_name          = "${var.name_prefix}-web-cpu-high"
  alarm_description   = "Web tier average CPU > ${var.cpu_high_threshold}% for 2 consecutive 5-minute periods"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions = {
    AutoScalingGroupName = var.web_asg_name
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "app_cpu_high" {
  alarm_name          = "${var.name_prefix}-app-cpu-high"
  alarm_description   = "App tier average CPU > ${var.cpu_high_threshold}% for 2 consecutive 5-minute periods"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions = {
    AutoScalingGroupName = var.app_asg_name
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

# Low-CPU alarms are informational (no notification): they highlight
# over-provisioning when reviewing the dashboard / alarm list.
resource "aws_cloudwatch_metric_alarm" "web_cpu_low" {
  alarm_name          = "${var.name_prefix}-web-cpu-low"
  alarm_description   = "Informational: web tier average CPU < ${var.cpu_low_threshold}% for 1 hour (consider smaller instances)"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 12
  threshold           = var.cpu_low_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    AutoScalingGroupName = var.web_asg_name
  }
}

resource "aws_cloudwatch_metric_alarm" "app_cpu_low" {
  alarm_name          = "${var.name_prefix}-app-cpu-low"
  alarm_description   = "Informational: app tier average CPU < ${var.cpu_low_threshold}% for 1 hour (consider smaller instances)"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 12
  threshold           = var.cpu_low_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    AutoScalingGroupName = var.app_asg_name
  }
}

# Custom metric from the CloudWatch agent (aggregated per ASG).
resource "aws_cloudwatch_metric_alarm" "app_memory_high" {
  alarm_name          = "${var.name_prefix}-app-memory-high"
  alarm_description   = "App tier memory used > ${var.memory_high_threshold}% (CloudWatch agent metric)"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.memory_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions = {
    AutoScalingGroupName = var.app_asg_name
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

# ------------------------------------------------------------------ ALB ----
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name_prefix}-alb-5xx"
  alarm_description   = "Public ALB generated more than ${var.alb_5xx_threshold} 5xx responses in 5 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alb_5xx_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${var.name_prefix}-alb-target-response-time"
  alarm_description   = "Public ALB average target response time > ${var.alb_latency_threshold}s"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.alb_latency_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "web_unhealthy_hosts" {
  alarm_name          = "${var.name_prefix}-web-unhealthy-hosts"
  alarm_description   = "One or more web targets behind the public ALB are unhealthy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.web_target_group_arn_suffix
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "app_unhealthy_hosts" {
  alarm_name          = "${var.name_prefix}-app-unhealthy-hosts"
  alarm_description   = "One or more app targets behind the internal ALB are unhealthy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = var.internal_alb_arn_suffix
    TargetGroup  = var.app_target_group_arn_suffix
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "app_5xx" {
  alarm_name          = "${var.name_prefix}-app-5xx"
  alarm_description   = "Application returned more than ${var.app_5xx_threshold} 5xx responses in 5 minutes (log metric filter)"
  namespace           = var.custom_metric_namespace
  metric_name         = aws_cloudwatch_log_metric_filter.app_5xx.metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.app_5xx_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ------------------------------------------------------------------ RDS ----
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  alarm_description   = "RDS CPU > ${var.cpu_high_threshold}% for 2 consecutive 5-minute periods"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  alarm_name          = "${var.name_prefix}-rds-free-storage-low"
  alarm_description   = "RDS free storage < ${var.rds_free_storage_threshold_gb} GB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.rds_free_storage_threshold_gb * 1024 * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"
  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.name_prefix}-rds-connections-high"
  alarm_description   = "RDS connections > ${var.rds_connections_threshold}"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.rds_connections_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

# ------------------------------------------------------------ Dashboard ----
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU utilization (by ASG)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.web_asg_name, { label = "web" }],
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.app_asg_name, { label = "app" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Memory used % (CloudWatch agent)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["CWAgent", "mem_used_percent", "AutoScalingGroupName", var.web_asg_name, { label = "web" }],
            ["CWAgent", "mem_used_percent", "AutoScalingGroupName", var.app_asg_name, { label = "app" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Public ALB requests & errors"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Target response time (s)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { label = "public ALB" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.internal_alb_arn_suffix, { label = "internal ALB" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          title   = "RDS CPU %"
          region  = var.aws_region
          view    = "timeSeries"
          stat    = "Average"
          period  = 300
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          title   = "RDS free storage (bytes)"
          region  = var.aws_region
          view    = "timeSeries"
          stat    = "Minimum"
          period  = 300
          metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_id]]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          title   = "RDS connections"
          region  = var.aws_region
          view    = "timeSeries"
          stat    = "Maximum"
          period  = 300
          metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_instance_id]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "Application errors (log metric filters)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            [var.custom_metric_namespace, "App5xxCount"],
            [var.custom_metric_namespace, "AppErrorCount"],
          ]
        }
      },
      {
        type   = "alarm"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title = "Alarm status"
          alarms = [
            aws_cloudwatch_metric_alarm.web_cpu_high.arn,
            aws_cloudwatch_metric_alarm.app_cpu_high.arn,
            aws_cloudwatch_metric_alarm.alb_5xx.arn,
            aws_cloudwatch_metric_alarm.alb_latency.arn,
            aws_cloudwatch_metric_alarm.rds_cpu_high.arn,
            aws_cloudwatch_metric_alarm.rds_free_storage_low.arn,
            aws_cloudwatch_metric_alarm.app_unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.app_5xx.arn,
          ]
        }
      },
    ]
  })
}
