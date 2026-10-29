# Monitoring

Everything in this document is created by `terraform/modules/cloudwatch` (plus the CloudWatch agent
configuration embedded in the launch templates in `terraform/modules/ec2/user_data/`).

## 1. Overview

```
 EC2 / ASG ──┐  AWS/EC2 metrics (1-min detailed monitoring)
 ALB (x2) ───┤  AWS/ApplicationELB metrics
 RDS ────────┤  AWS/RDS metrics                         ┌──────────────┐     ┌────────────┐
 CW agent ───┤  CWAgent: mem_used_percent, disk ───────►│  CloudWatch  │────►│ SNS topic  │──► e-mail
 App logs ───┘  /aws/ec2/app-tier ─► metric filters ───►│  alarms (13) │     │ <p>-alarms │
                                                        └──────┬───────┘     └────────────┘
                                                               ▼
                                                     Dashboard <prefix>-overview
```

## 2. Alarms

`<p>` is the name prefix `<project_name>-<environment>` (e.g. `mtwa-dev`). Unless stated otherwise, alarms send
notifications to SNS on both **ALARM** and **OK** transitions.

| Alarm name | Namespace / metric | Dimension | Statistic · period | Condition | Notifies |
|------------|--------------------|-----------|--------------------|-----------|----------|
| `<p>-web-cpu-high` | `AWS/EC2` `CPUUtilization` | web ASG | Average · 5 min | > 80 % for 2 periods | ✅ |
| `<p>-app-cpu-high` | `AWS/EC2` `CPUUtilization` | app ASG | Average · 5 min | > 80 % for 2 periods | ✅ |
| `<p>-web-cpu-low` | `AWS/EC2` `CPUUtilization` | web ASG | Average · 5 min | < 10 % for 12 periods (1 h) | — informational |
| `<p>-app-cpu-low` | `AWS/EC2` `CPUUtilization` | app ASG | Average · 5 min | < 10 % for 12 periods (1 h) | — informational |
| `<p>-app-memory-high` | `CWAgent` `mem_used_percent` | app ASG | Average · 5 min | > 85 % for 2 periods | ✅ |
| `<p>-alb-5xx` | `AWS/ApplicationELB` `HTTPCode_ELB_5XX_Count` | public ALB | Sum · 5 min | > 10 for 1 period | ✅ |
| `<p>-alb-target-response-time` | `AWS/ApplicationELB` `TargetResponseTime` | public ALB | Average · 5 min | > 1 s for 2 periods | ✅ |
| `<p>-web-unhealthy-hosts` | `AWS/ApplicationELB` `UnHealthyHostCount` | public ALB + web TG | Maximum · 1 min | > 0 for 5 periods | ✅ |
| `<p>-app-unhealthy-hosts` | `AWS/ApplicationELB` `UnHealthyHostCount` | internal ALB + app TG | Maximum · 1 min | > 0 for 5 periods | ✅ |
| `<p>-app-5xx` | `MultiTierApp` `App5xxCount` | — | Sum · 5 min | > 10 for 1 period | ✅ |
| `<p>-rds-cpu-high` | `AWS/RDS` `CPUUtilization` | DB instance | Average · 5 min | > 80 % for 2 periods | ✅ |
| `<p>-rds-free-storage-low` | `AWS/RDS` `FreeStorageSpace` | DB instance | Minimum · 5 min | < 2 GB | ✅ |
| `<p>-rds-connections-high` | `AWS/RDS` `DatabaseConnections` | DB instance | Maximum · 5 min | > 50 for 2 periods | ✅ |

Missing-data handling: traffic-driven metrics (ALB, 5xx) treat missing data as *not breaching*; resource
metrics keep the default (*missing*) so a stopped data source surfaces as *Insufficient data*.

All thresholds are module variables (`cpu_high_threshold`, `memory_high_threshold`, `alb_5xx_threshold`,
`alb_latency_threshold`, `rds_free_storage_threshold_gb`, `rds_connections_threshold`, …) and can be overridden
in the `module "cloudwatch"` block of `terraform/main.tf`.

### Alarms vs. auto scaling

Scaling is handled separately by **target-tracking policies** (average CPU 60 %) in the EC2 module; AWS creates
and manages their alarms (`TargetTracking-*`). The alarms above are for **notification**: if CPU stays above
80 % even though the ASG is scaling, you are likely at `max_size` and need attention.

## 3. SNS notifications

The topic `<p>-alarms` is created with a policy allowing `cloudwatch.amazonaws.com` to publish.

**E-mail via Terraform** — set `alarm_email` in `terraform.tfvars`, apply, then click the link in the
*AWS Notification - Subscription Confirmation* e-mail. Pending subscriptions receive nothing.

**Additional subscribers via CLI:**

```bash
TOPIC=$(terraform -chdir=terraform output -raw sns_topic_arn)

aws sns subscribe --topic-arn "$TOPIC" --protocol email --notification-endpoint teammate@example.com
aws sns subscribe --topic-arn "$TOPIC" --protocol sms   --notification-endpoint +15555550123
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC"
```

For Slack or Microsoft Teams, connect the topic to **AWS Chatbot** (Amazon Q Developer in chat applications)
or subscribe an HTTPS webhook / Lambda function.

**Test the notification path:**

```bash
aws cloudwatch set-alarm-state --alarm-name mtwa-dev-alb-5xx \
  --state-value ALARM --state-reason "Manual notification test"
# The alarm returns to its real state at the next evaluation (≤ 5 min) and sends an OK message.
```

## 4. Logs

| Log group | Retention | Streams | Source |
|-----------|-----------|---------|--------|
| `/aws/ec2/app-tier` | 14 days | `<instance-id>/app`, `<instance-id>/user-data` | CloudWatch agent on app instances |
| `/aws/ec2/web-tier` | 14 days | `<instance-id>/nginx-access`, `/nginx-error`, `/user-data` | CloudWatch agent on web instances |
| `/aws/rds/instance/<p>-mysql/error`, `/slowquery` | never expire (AWS default) | — | RDS log exports |

The application writes **JSON lines** (see `app/src/middleware/logger.js`):

```json
{"time":"2026-10-29T01:39:40.802Z","type":"access","level":"info","requestId":"9548d365-…","method":"GET","path":"/api/items","status":200,"durationMs":2.4}
{"time":"2026-10-29T01:40:02.113Z","type":"app","level":"error","message":"Unhandled request error","error":"connect ETIMEDOUT"}
```

ALB health checks returning 200 are not logged to keep ingestion costs low.

### Useful Logs Insights queries

```sql
-- Slowest API calls in the selected window
fields @timestamp, method, path, status, durationMs
| filter type = "access"
| sort durationMs desc
| limit 20

-- Error rate per 5 minutes
filter type = "access"
| stats sum(status >= 500) as errors, count(*) as requests, (errors / requests) * 100 as error_pct by bin(5m)

-- Latest application errors
fields @timestamp, message, error, requestId
| filter level = "error"
| sort @timestamp desc
| limit 50
```

## 5. Custom metrics

| Metric | Namespace | Produced by | Dimensions |
|--------|-----------|-------------|------------|
| `mem_used_percent` | `CWAgent` | CloudWatch agent (60 s) | `AutoScalingGroupName`, `InstanceId` + ASG aggregate |
| `disk_used_percent` | `CWAgent` | CloudWatch agent (60 s), path `/` | same + `path`, `device`, `fstype` |
| `App5xxCount` | `MultiTierApp` | Metric filter `{ $.type = "access" && $.status >= 500 }` | none |
| `AppErrorCount` | `MultiTierApp` | Metric filter `{ $.level = "error" }` | none |

The agent config lives in each user-data script (`/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`
on the instance). After editing it on a live instance:

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

## 6. Dashboard

`terraform output -raw dashboard_url` opens `<p>-overview`, which shows EC2 CPU and memory per tier, ALB
requests/4xx/5xx, target response time for both ALBs, RDS CPU/storage/connections, application error metrics
and an alarm-status widget.

## 7. Extending monitoring

### Add a metric alarm

Append to `terraform/modules/cloudwatch/main.tf` (add any new inputs to `variables.tf`):

```hcl
resource "aws_cloudwatch_metric_alarm" "rds_read_latency" {
  alarm_name          = "${var.name_prefix}-rds-read-latency"
  alarm_description   = "RDS read latency > 20 ms"
  namespace           = "AWS/RDS"
  metric_name         = "ReadLatency"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 0.02
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}
```

### Add a log-based metric

```hcl
resource "aws_cloudwatch_log_metric_filter" "slow_requests" {
  name           = "${var.name_prefix}-slow-requests"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.type = \"access\" && $.durationMs > 1000 }"

  metric_transformation {
    name          = "SlowRequestCount"
    namespace     = var.custom_metric_namespace
    value         = "1"
    default_value = "0"
  }
}
```

### Other ideas

- **Composite alarm** that only pages when `alb-5xx` **and** `app-unhealthy-hosts` are both in ALARM.
- **Anomaly detection** on `RequestCount` (`aws_cloudwatch_metric_alarm` with `threshold_metric_id` + `ANOMALY_DETECTION_BAND`).
- **CloudWatch Synthetics** canary hitting `/ready` every 5 minutes from outside the VPC.
- **RDS Enhanced Monitoring** (`monitoring_interval = 60` + monitoring role) for OS-level DB metrics.
- **Container Insights / X-Ray** if the app moves to ECS or adds tracing.
