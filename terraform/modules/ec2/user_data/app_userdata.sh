#!/bin/bash
# -----------------------------------------------------------------------------
# App tier bootstrap (Amazon Linux 2023) — rendered by Terraform templatefile().
#   * Installs Node.js 20, pulls the app bundle from S3, runs `npm ci`.
#   * DB credentials are read from Secrets Manager at every service start by
#     /opt/app/bin/start.sh (never written into user data or onto disk).
#   * Runs DB migrations, then the app under systemd as an unprivileged user.
#   * CloudWatch agent ships memory/disk metrics and app logs.
# App bundle version: ${app_bundle_version}
# -----------------------------------------------------------------------------
set -euo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[app] bootstrap starting at $(date -Is)"

AWS_REGION="${aws_region}"
ARTIFACTS_BUCKET="${artifacts_bucket}"
APP_BUNDLE_KEY="${app_bundle_key}"
APP_HOME="/opt/app"
RELEASE_DIR="$APP_HOME/releases/${app_bundle_version}"

yum update -y
yum install -y unzip jq amazon-cloudwatch-agent

# --------------------------------------------------------------- Node.js ----
if ! curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -; then
  echo "[app] NodeSource setup failed, falling back to the AL2023 nodejs20 package"
fi
if yum install -y nodejs && node -v | grep -q '^v2[0-9]'; then
  echo "[app] installed Node.js $(node -v) from NodeSource"
else
  yum install -y nodejs20 nodejs20-npm
  alternatives --set node /usr/bin/node-20 2>/dev/null || ln -sf /usr/bin/node-20 /usr/bin/node
  [ -x /usr/bin/npm ] || ln -sf /usr/bin/npm-20 /usr/bin/npm
  echo "[app] installed Node.js $(node -v) from AL2023 repos"
fi

# ------------------------------------------------------------ app user ----
id -u nodeapp >/dev/null 2>&1 || useradd --system --home-dir "$APP_HOME" --shell /sbin/nologin nodeapp
mkdir -p "$APP_HOME/releases" "$APP_HOME/bin" /etc/app /var/log/app

# --------------------------------------------------------- app bundle ----
for attempt in $(seq 1 30); do
  if aws s3 cp "s3://$ARTIFACTS_BUCKET/$APP_BUNDLE_KEY" /tmp/app.zip --region "$AWS_REGION" --only-show-errors; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo "[app] ERROR: could not download s3://$ARTIFACTS_BUCKET/$APP_BUNDLE_KEY" >&2
    exit 1
  fi
  echo "[app] bundle not available yet (attempt $attempt), retrying in 20s"
  sleep 20
done

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
unzip -q -o /tmp/app.zip -d "$RELEASE_DIR"
rm -f /tmp/app.zip

cd "$RELEASE_DIR"
export HOME=/root
npm ci --omit=dev --no-audit --no-fund
ln -sfn "$RELEASE_DIR" "$APP_HOME/current"
chown -R nodeapp:nodeapp "$APP_HOME" /var/log/app

# ------------------------------------------------- runtime environment ----
# Non-secret configuration only. Credentials come from Secrets Manager.
cat > /etc/app/app.env <<ENV
NODE_ENV=production
APP_ENV=${environment}
PORT=${app_port}
AWS_REGION=$AWS_REGION
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_SECRET_ARN=${db_secret_arn}
APP_VERSION=${app_bundle_version}
ENV
chmod 0644 /etc/app/app.env

cat > "$APP_HOME/bin/start.sh" <<'START'
#!/bin/bash
# Loads config + DB credentials, runs migrations, then execs the Node.js app.
set -euo pipefail
set -a
. /etc/app/app.env
set +a

SECRET_JSON="$(aws secretsmanager get-secret-value \
  --secret-id "$DB_SECRET_ARN" --region "$AWS_REGION" \
  --query SecretString --output text)"
DB_USER="$(printf '%s' "$SECRET_JSON" | jq -r '.username')"
DB_PASSWORD="$(printf '%s' "$SECRET_JSON" | jq -r '.password')"
export DB_USER DB_PASSWORD
unset SECRET_JSON

cd /opt/app/current
node scripts/migrate.js
exec node src/server.js
START
chmod 0755 "$APP_HOME/bin/start.sh"
chown nodeapp:nodeapp "$APP_HOME/bin/start.sh"

# --------------------------------------------------------------- systemd ----
cat > /etc/systemd/system/app.service <<'UNIT'
[Unit]
Description=Multi-tier Node.js application
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=nodeapp
Group=nodeapp
WorkingDirectory=/opt/app/current
ExecStart=/opt/app/bin/start.sh
Restart=always
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGTERM
StandardOutput=append:/var/log/app/app.log
StandardError=append:/var/log/app/app.log
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/logrotate.d/app <<'ROTATE'
/var/log/app/*.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    copytruncate
}
ROTATE

systemctl daemon-reload
systemctl enable --now app.service

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
            "file_path": "/var/log/app/app.log",
            "log_group_name": "${app_log_group_name}",
            "log_stream_name": "{instance_id}/app"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "${app_log_group_name}",
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

# Wait for the app to answer locally so failures are visible in user-data.log.
for attempt in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${app_port}/health" >/dev/null; then
    echo "[app] health check passed"
    break
  fi
  sleep 5
done

echo "[app] bootstrap complete at $(date -Is)"
