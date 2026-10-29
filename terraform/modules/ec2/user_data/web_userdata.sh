#!/bin/bash
# -----------------------------------------------------------------------------
# Web tier bootstrap (Amazon Linux 2023) — rendered by Terraform templatefile().
#   * nginx serves static assets pulled from S3 and reverse-proxies /api,
#     /health and /ready to the app tier through the internal ALB.
#   * CloudWatch agent ships memory/disk metrics and nginx logs.
# Static assets version: ${static_version}
# -----------------------------------------------------------------------------
set -euo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[web] bootstrap starting at $(date -Is)"

AWS_REGION="${aws_region}"
STATIC_BUCKET="${static_assets_bucket}"
APP_UPSTREAM="http://${app_alb_dns}:${app_port}"
WEB_ROOT="/usr/share/nginx/html/app"

yum update -y
yum install -y nginx amazon-cloudwatch-agent

# ---------------------------------------------------------------- static ----
mkdir -p "$WEB_ROOT"
for attempt in 1 2 3 4 5; do
  if aws s3 sync "s3://$STATIC_BUCKET/" "$WEB_ROOT/" --region "$AWS_REGION" --only-show-errors; then
    break
  fi
  echo "[web] static sync failed (attempt $attempt), retrying in 10s"
  sleep 10
done

if [ ! -f "$WEB_ROOT/index.html" ]; then
  cat > "$WEB_ROOT/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Multi-tier web app</title></head>
<body><h1>Multi-tier web app</h1><p>Static assets not yet published. API: <a href="/api/items">/api/items</a></p></body></html>
HTML
fi

# ----------------------------------------------------------------- nginx ----
cat > /etc/nginx/nginx.conf <<NGINX
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for" rt=\$request_time urt=\$upstream_response_time';

    access_log /var/log/nginx/access.log main;

    sendfile            on;
    tcp_nopush          on;
    keepalive_timeout   65;
    types_hash_max_size 4096;
    server_tokens       off;
    client_max_body_size 1m;

    include      /etc/nginx/mime.types;
    default_type application/octet-stream;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    # VPC DNS resolver: re-resolve the internal ALB (its IPs change over time).
    resolver 169.254.169.253 valid=30s ipv6=off;
    resolver_timeout 5s;

    server {
        listen 80 default_server;
        server_name _;
        root $WEB_ROOT;

        set \$app_upstream $APP_UPSTREAM;

        add_header X-Content-Type-Options nosniff always;
        add_header X-Frame-Options DENY always;
        add_header Referrer-Policy strict-origin-when-cross-origin always;

        # Local liveness check for nginx itself (does not touch the app tier).
        location = /nginx-health {
            access_log off;
            default_type text/plain;
            return 200 "ok\n";
        }

        location ~ ^/(api/|health\$|ready\$) {
            proxy_pass \$app_upstream;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header X-Request-Id \$request_id;
            proxy_set_header Connection "";
            proxy_connect_timeout 5s;
            proxy_read_timeout 30s;
        }

        location / {
            try_files \$uri \$uri/ /index.html;
            expires 5m;
        }
    }
}
NGINX

nginx -t
systemctl enable --now nginx
systemctl reload nginx

# ------------------------------------------------------ CloudWatch agent ----
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWAGENT'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
      "InstanceId": "$${aws:InstanceId}"
    },
    "aggregation_dimensions": [["AutoScalingGroupName"]],
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "${web_log_group_name}",
            "log_stream_name": "{instance_id}/nginx-access"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "${web_log_group_name}",
            "log_stream_name": "{instance_id}/nginx-error"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "${web_log_group_name}",
            "log_stream_name": "{instance_id}/user-data"
          }
        ]
      }
    }
  }
}
CWAGENT

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "[web] bootstrap complete (environment=${environment}) at $(date -Is)"
