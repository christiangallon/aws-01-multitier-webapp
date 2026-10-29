# Setup Guide

Step-by-step instructions to deploy, verify, update and remove the AWS Multi-Tier Web App.

---

## 1. Prerequisites

### 1.1 Tools

| Tool | Minimum | Install |
|------|---------|---------|
| AWS CLI | v2 | <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html> |
| Terraform | 1.5 | <https://developer.hashicorp.com/terraform/install> |
| Node.js + npm | 20 | <https://nodejs.org/> (or `nvm install 20`) |
| git, zip, jq, curl | any | your OS package manager |
| Session Manager plugin *(optional)* | latest | <https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html> |

```bash
aws --version && terraform version && node -v && jq --version
```

### 1.2 AWS account and permissions

Use an IAM user/role (ideally via IAM Identity Center) that can manage: VPC/EC2, Elastic Load Balancing,
Auto Scaling, RDS, S3, IAM (roles, instance profiles, policies), Secrets Manager, CloudWatch (alarms,
logs, dashboards), SNS and DynamoDB. `AdministratorAccess` in a sandbox account is the simplest option for a lab.

> ⚠️ This stack incurs charges (≈ $0.19/hour, see [cost-estimate.md](cost-estimate.md)). Destroy it when you are done.

## 2. Configure AWS credentials

Pick one:

```bash
# A) IAM Identity Center (recommended)
aws configure sso                 # creates a named profile
aws sso login --profile my-sandbox
export AWS_PROFILE=my-sandbox

# B) Access keys
aws configure                     # prompts for key, secret, region (us-east-1), output (json)
```

Verify:

```bash
aws sts get-caller-identity
```

## 3. Clone the repository

```bash
git clone https://github.com/christiangallon/aws-01-multitier-webapp.git
cd aws-01-multitier-webapp
```

## 4. Create the Terraform state backend

Terraform state is stored in a versioned, encrypted S3 bucket with a DynamoDB lock table.

```bash
./scripts/init-backend.sh -r us-east-1 -p mtwa -e dev
```

This creates (idempotently):

- S3 bucket `mtwa-tfstate-<account-id>-us-east-1` (versioning, SSE-S3, public access block, TLS-only)
- DynamoDB table `mtwa-tflock` (on-demand, `LockID` key)
- `terraform/backend.hcl` (git-ignored) with the backend settings

> Prefer local state for a quick experiment? Delete the `backend "s3" {}` block from `terraform/main.tf`
> and skip this step.

## 5. Configure variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit at least:

| Variable | Why |
|----------|-----|
| `alarm_email` | Address that receives CloudWatch alarm notifications |
| `admin_cidr` | Your public IP `/32` (`curl -s https://checkip.amazonaws.com`) — only used by the optional bastion |
| `project_name`, `environment` | Resource naming; must match the values used with `init-backend.sh` if you changed them |

Other useful toggles:

| Variable | Default | Notes |
|----------|---------|-------|
| `db_multi_az` | `false` | `true` for production-like HA (≈ +$15/month) |
| `web_instance_type` / `app_instance_type` | `t3.micro` / `t3.small` | |
| `*_min_size` / `*_max_size` / `*_desired_capacity` | 1 / 3 / 1 | per tier |
| `enable_bastion` + `bastion_key_name` | `false` | SSH jump host; SSM works without it |
| `enable_alb_access_logs` | `true` | ALB logs → access-logs bucket |
| `s3_force_destroy` | `true` | Set `false` to protect bucket contents on destroy |
| `secret_recovery_window_in_days` | `0` | `0` allows immediate re-creation after destroy |

## 6. Initialise, plan and apply

```bash
cd terraform
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

What happens during `apply` (≈ 15–20 minutes):

1. VPC, subnets, IGW, NAT gateway, route tables, S3 endpoint
2. Security groups, S3 buckets, IAM role
3. RDS instance (the slowest step, ~8–12 min) and its Secrets Manager secret
4. `app/` is zipped to `terraform/.build/app.zip` and uploaded to `s3://<prefix>-app-artifacts/releases/app.zip`;
   `app/public/*` is uploaded to the static-assets bucket
5. ALBs, launch templates, Auto Scaling groups, scaling policies
6. SNS topic, log groups, metric filters, alarms, dashboard

Useful outputs:

```bash
terraform output                     # everything
terraform output -raw app_url        # http://<alb-dns>
terraform output -raw dashboard_url
```

## 7. Confirm the SNS subscription

If you set `alarm_email`, AWS sends an e-mail titled **"AWS Notification - Subscription Confirmation"**.
Click **Confirm subscription** — notifications are not delivered until you do.

## 8. Verify the deployment

Instances need 3–6 minutes after `apply` to install packages and pass health checks.

```bash
APP_URL=$(terraform output -raw app_url)

# Liveness + DB connectivity
curl -s "$APP_URL/health" | jq
# {"status":"ok","db":"up","uptimeSeconds":..., "version":"<bundle-md5>", "hostname":"ip-10-0-11-..."}

# Readiness (200 only when MySQL is reachable)
curl -s -o /dev/null -w '%{http_code}\n' "$APP_URL/ready"

# CRUD
ID=$(curl -s -X POST "$APP_URL/api/items" -H 'Content-Type: application/json' \
      -d '{"name":"First item","description":"Hello from RDS"}' | jq -r .data.id)
curl -s "$APP_URL/api/items/$ID" | jq
curl -s -X PUT "$APP_URL/api/items/$ID" -H 'Content-Type: application/json' -d '{"name":"Renamed"}' | jq
curl -s "$APP_URL/api/items" | jq '.count'
curl -s -X DELETE -o /dev/null -w '%{http_code}\n' "$APP_URL/api/items/$ID"   # 204
```

Open `$APP_URL` in a browser for the web UI.

### Check the AWS console

| Where | What to look for |
|-------|------------------|
| EC2 → Target groups | `*-web-tg` and `*-app-tg` targets **healthy** |
| EC2 → Auto Scaling groups | `*-web-asg` and `*-app-asg` with 1 InService instance each |
| RDS → Databases | `*-mysql` **Available**, not publicly accessible |
| CloudWatch → Alarms | alarms in **OK** (some may show *Insufficient data* for the first minutes) |
| CloudWatch → Log groups | `/aws/ec2/app-tier` streams `<instance-id>/app` with JSON lines |
| CloudWatch → Dashboards | `*-overview` |

### Seed sample data (optional)

```bash
ASG=$(terraform output -raw app_asg_name)
IID=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
      --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)
aws ssm start-session --target "$IID"
# inside the session:
sudo -u nodeapp bash -c 'set -a; . /etc/app/app.env; set +a;
  S=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" --query SecretString --output text);
  export DB_USER=$(echo "$S" | jq -r .username) DB_PASSWORD=$(echo "$S" | jq -r .password);
  cd /opt/app/current && node scripts/seed.js'
```

## 9. Deploy application changes

Edit code in `app/`, run the tests (`cd app && npm test`), then either:

```bash
# Option A: Terraform (packages, uploads, rolls both tiers automatically)
cd terraform && terraform apply

# Option B: deploy script (no infrastructure changes)
./scripts/deploy.sh              # test → zip → upload → rolling refresh → /health smoke test
./scripts/deploy.sh --skip-web   # only roll the app tier
```

## 10. Troubleshooting

| Symptom | Check |
|---------|-------|
| `502 Bad Gateway` from the ALB | Web instance still booting, or nginx down: `aws ssm start-session` → `sudo systemctl status nginx`, `/var/log/user-data.log` |
| `504` / `/health` times out | App tier unhealthy: check `*-app-tg` targets; on an app instance `sudo systemctl status app`, `sudo tail -f /var/log/app/app.log` |
| `/health` shows `"db":"down"` | RDS still creating, SG rule, or secret access: `sudo systemctl stop app && sudo -u nodeapp /opt/app/bin/start.sh` prints the error (Ctrl-C, then `sudo systemctl start app`) |
| App instances keep being replaced | Bootstrap failing (e.g. npm registry unreachable → check NAT route). Logs are in `/aws/ec2/app-tier` → `<instance-id>/user-data` |
| `terraform init` asks for backend values | Run `init-backend.sh` and pass `-backend-config=backend.hcl` |
| `BucketAlreadyExists` | Bucket names include a random suffix; if you changed `project_name` to something long, shorten it |
| Secret "scheduled for deletion" on re-apply | Set `secret_recovery_window_in_days = 0` (default) or restore/force-delete the secret |

Bootstrap logs on any instance: `/var/log/user-data.log` (also shipped to CloudWatch Logs).

## 11. Tear down

```bash
./scripts/destroy.sh                   # confirm by typing the environment name
./scripts/destroy.sh --destroy-backend # also remove the state bucket + lock table
```

Verify in the console that no NAT gateways, load balancers, RDS instances or Elastic IPs remain.
