# AWS Multi-Tier Web App

[![Terraform](https://img.shields.io/badge/IaC-Terraform%20%3E%3D1.5-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Node.js](https://img.shields.io/badge/App-Node.js%2020-339933?logo=node.js)](https://nodejs.org/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazonaws)](https://aws.amazon.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](#license)

A monitored, three-tier web application deployed into a custom VPC with **Terraform**:
an internet-facing **Application Load Balancer** in front of an **nginx web tier**, a **Node.js/Express
application tier** in private subnets, a **MySQL RDS** database, **S3** for artifacts/static
assets/logs, and **CloudWatch** alarms, logs and a dashboard with **SNS** email notifications.

> **Level:** Beginner · **Estimated effort:** 24–32 hours · **Region:** `us-east-1` (configurable)

---

## Table of contents

- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick start (5 steps)](#quick-start-5-steps)
- [Folder structure](#folder-structure)
- [The application](#the-application)
- [CloudWatch alarms](#cloudwatch-alarms)
- [Cost estimate (dev)](#cost-estimate-dev)
- [Deploying new releases](#deploying-new-releases)
- [Destroying the stack](#destroying-the-stack)
- [Security notes](#security-notes)
- [Documentation](#documentation)
- [License](#license)

---

## Architecture

```
                                   Internet
                                       │
                               ┌───────▼────────┐
                               │ Internet GW    │
                               └───────┬────────┘
┌──────────────────────────────────────┼──────────────── VPC 10.0.0.0/16 ─────────────────┐
│                                      │                                                  │
│   Public subnets       ┌─────────────▼──────────────┐                                   │
│   10.0.1.0/24 (1a)     │  Public ALB  (:80 / :443)  │                                   │
│   10.0.2.0/24 (1b)     └─────────────┬──────────────┘                                   │
│                          ┌───────────┴────────────┐        ┌──────────────┐             │
│                          ▼                        ▼        │ NAT Gateway  │             │
│                   ┌─────────────┐          ┌─────────────┐ │ (subnet 1a)  │             │
│                   │ Web (nginx) │   ...    │ Web (nginx) │ └──────▲───────┘             │
│                   │  t3.micro   │ ASG 1–3  │  t3.micro   │        │ outbound only       │
│                   └──────┬──────┘          └──────┬──────┘        │                     │
│ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│   Private subnets        └───────────┬────────────┘               │                     │
│   10.0.11.0/24 (1a)       ┌──────────▼───────────┐                │                     │
│   10.0.12.0/24 (1b)       │ Internal ALB (:3000) │                │                     │
│                           └──────────┬───────────┘                │                     │
│                          ┌───────────┴────────────┐               │                     │
│                          ▼                        ▼               │                     │
│                   ┌─────────────┐          ┌─────────────┐        │                     │
│                   │ App Node.js │   ...    │ App Node.js │────────┘                     │
│                   │  t3.small   │ ASG 1–3  │  t3.small   │                              │
│                   └──────┬──────┘          └──────┬──────┘                              │
│                          └───────────┬────────────┘                                     │
│                              ┌───────▼────────┐  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ┐                    │
│                              │ RDS MySQL 8.0  │    Standby (opt.     │                    │
│                              │  db.t3.micro   │──│ Multi-AZ, 1b)   │                    │
│                              └────────────────┘  └ ─ ─ ─ ─ ─ ─ ─ ─ ┘                    │
└─────────────────────────────────────────────────────────────────────────────────────────┘

  S3 (via VPC gateway endpoint):  app-artifacts · static-assets · access-logs
  CloudWatch: metrics · alarms → SNS email · logs (/aws/ec2/app-tier, /aws/ec2/web-tier) · dashboard
  Secrets Manager: RDS credentials (read by the app tier at start-up)
```

**Request flow:** browser → public ALB → nginx (serves the static UI pulled from S3) → `/api/*`,
`/health`, `/ready` are proxied to the internal ALB → Node.js app → RDS MySQL.

See [docs/architecture.md](docs/architecture.md) for the full design, security-group matrix and design decisions.

## Features

| Area | What you get |
|------|--------------|
| **Networking** | VPC `10.0.0.0/16`, 2 public + 2 private subnets in 2 AZs, IGW, NAT gateway, S3 gateway endpoint |
| **Compute** | Public ALB, internal ALB, web & app Auto Scaling groups (min 1 / max 3), launch templates with **IMDSv2**, encrypted gp3 volumes, CPU target-tracking scaling, rolling instance refresh |
| **Data** | RDS MySQL 8.0, encrypted, private, parameter group, optional **Multi-AZ**, credentials generated into **Secrets Manager** |
| **Storage** | 3 S3 buckets with versioning, SSE-S3, public access block, TLS-only policies, lifecycle rules (IA 30d → Glacier 90d → expire 365d) and server access logging |
| **Identity** | One EC2 role: SSM Session Manager, CloudWatch agent, S3 read, secret read — no SSH keys required |
| **Monitoring** | 13 CloudWatch alarms, SNS email topic, CloudWatch agent (memory/disk + log shipping), JSON log metric filters, dashboard |
| **App** | Node.js 20 + Express REST API with MySQL pool, health/readiness probes, CRUD for `items`, migrations, seed data, tests |
| **Ops** | `init-backend.sh` (S3 + DynamoDB state backend), `deploy.sh` (zero-downtime release), `destroy.sh` (guarded teardown) |

## Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | v2 | `aws --version` |
| [Terraform](https://developer.hashicorp.com/terraform/install) | **>= 1.5** | `terraform version` |
| [Node.js](https://nodejs.org/) | **>= 20** | `node -v` |
| `zip`, `jq`, `curl` | any | used by `scripts/deploy.sh` |

You also need an AWS account with permissions for VPC, EC2, ELB, Auto Scaling, RDS, S3, IAM,
Secrets Manager, CloudWatch, SNS and DynamoDB, and configured credentials (`aws configure` or `AWS_PROFILE`).

## Quick start (5 steps)

```bash
# 1. Clone
git clone https://github.com/christiangallon/aws-01-multitier-webapp.git
cd aws-01-multitier-webapp

# 2. Create the remote-state backend (S3 bucket + DynamoDB lock table) → writes terraform/backend.hcl
./scripts/init-backend.sh -r us-east-1

# 3. Configure variables (set alarm_email and admin_cidr at minimum)
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR terraform/terraform.tfvars

# 4. Provision everything (≈ 15–20 min, RDS is the slowest part)
cd terraform
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan

# 5. Verify
APP_URL=$(terraform output -raw app_url)
curl -s "$APP_URL/health" | jq
curl -s -X POST "$APP_URL/api/items" -H 'Content-Type: application/json' \
     -d '{"name":"hello","description":"first item"}' | jq
curl -s "$APP_URL/api/items" | jq
open "$APP_URL"        # or xdg-open — the web UI
```

> Instances need a few minutes after `apply` to install packages and pass health checks.
> Confirm the SNS subscription e-mail to start receiving alarm notifications.

Full walkthrough: [docs/setup-guide.md](docs/setup-guide.md).

## Folder structure

```
aws-01-multitier-webapp/
├── README.md
├── LICENSE
├── .gitignore
├── terraform/
│   ├── main.tf                     # providers, backend, module wiring, app bundle upload
│   ├── variables.tf                # all inputs with defaults and validation
│   ├── outputs.tf                  # URLs, endpoints, bucket/ASG names, secret ARN
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── vpc/                    # VPC, subnets, IGW, NAT GW, route tables, S3 endpoint
│       ├── security_groups/        # alb, web, internal-alb, app, rds, bastion SGs
│       ├── ec2/                    # ALBs, target groups, launch templates, ASGs, scaling, bastion
│       │   └── user_data/
│       │       ├── web_userdata.sh # nginx + static assets from S3 + CloudWatch agent
│       │       └── app_userdata.sh # Node.js 20 + app bundle from S3 + systemd + CloudWatch agent
│       ├── rds/                    # MySQL 8.0, subnet/parameter groups, Secrets Manager secret
│       ├── s3/                     # artifacts, static-assets, access-logs buckets
│       ├── iam/                    # EC2 role + instance profile
│       └── cloudwatch/             # SNS, log groups, metric filters, alarms, dashboard
├── app/
│   ├── package.json / package-lock.json
│   ├── .env.example
│   ├── src/
│   │   ├── server.js               # Express app, /health, /ready, graceful shutdown
│   │   ├── db.js                   # mysql2 connection pool
│   │   ├── routes/items.js         # CRUD API
│   │   └── middleware/logger.js    # JSON access/app logging (morgan)
│   ├── scripts/
│   │   ├── migrate.js              # creates the items table (idempotent)
│   │   └── seed.js                 # sample data
│   ├── public/                     # static UI (uploaded to the static-assets bucket)
│   └── test/server.test.js         # node:test smoke + CRUD tests
├── scripts/
│   ├── init-backend.sh             # S3 state bucket + DynamoDB lock table
│   ├── deploy.sh                   # package → S3 → rolling instance refresh → smoke test
│   └── destroy.sh                  # confirmed teardown (+ optional backend removal)
└── docs/
    ├── architecture.md
    ├── setup-guide.md
    ├── monitoring.md
    └── cost-estimate.md
```

## The application

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness — always `200` while the process runs; JSON includes `db: up/down`, version, hostname |
| `GET` | `/ready` | Readiness — `200` if MySQL answers, otherwise `503` |
| `GET` | `/api/items?limit=&offset=` | List items (newest first) |
| `POST` | `/api/items` | Create `{ "name": "...", "description": "..." }` → `201` |
| `GET` | `/api/items/:id` | Get one item (UUID) |
| `PUT` | `/api/items/:id` | Update `name` and/or `description` |
| `DELETE` | `/api/items/:id` | Delete → `204` |

Run it locally against any MySQL 8 instance:

```bash
cd app
cp .env.example .env        # fill in DB_HOST / DB_USER / DB_PASSWORD
npm install
npm run migrate && npm run seed
npm run dev                 # http://localhost:3000
npm test                    # TEST_DB=1 npm test also runs the CRUD tests against your DB
```

On EC2 the app runs as the unprivileged `nodeapp` user under systemd. `/opt/app/bin/start.sh` reads
the DB credentials from Secrets Manager, runs `migrate.js`, then starts `src/server.js`.

## CloudWatch alarms

All alarms (except the informational low-CPU ones) notify the SNS topic `<prefix>-alarms` on ALARM and OK.

| Alarm | Metric | Condition |
|-------|--------|-----------|
| `web-cpu-high` | `AWS/EC2 CPUUtilization` (web ASG) | > 80 % avg, 2 × 5 min |
| `app-cpu-high` | `AWS/EC2 CPUUtilization` (app ASG) | > 80 % avg, 2 × 5 min |
| `web-cpu-low` / `app-cpu-low` | `AWS/EC2 CPUUtilization` | < 10 % for 1 h (informational, no notification) |
| `app-memory-high` | `CWAgent mem_used_percent` (app ASG) | > 85 %, 2 × 5 min |
| `alb-5xx` | `AWS/ApplicationELB HTTPCode_ELB_5XX_Count` | > 10 in 5 min |
| `alb-target-response-time` | `AWS/ApplicationELB TargetResponseTime` | > 1 s avg, 2 × 5 min |
| `web-unhealthy-hosts` / `app-unhealthy-hosts` | `UnHealthyHostCount` | > 0 for 5 min |
| `app-5xx` | `MultiTierApp App5xxCount` (log metric filter) | > 10 in 5 min |
| `rds-cpu-high` | `AWS/RDS CPUUtilization` | > 80 %, 2 × 5 min |
| `rds-free-storage-low` | `AWS/RDS FreeStorageSpace` | < 2 GB |
| `rds-connections-high` | `AWS/RDS DatabaseConnections` | > 50, 2 × 5 min |

Details, SNS setup and how to add alarms: [docs/monitoring.md](docs/monitoring.md).

## Cost estimate (dev)

Approximate on-demand prices in `us-east-1`, running 24×7 (730 h/month) with default settings and low traffic.
**Estimates only** — verify with the [AWS Pricing Calculator](https://calculator.aws/).

| Component | Configuration | ≈ USD / month |
|-----------|---------------|--------------:|
| EC2 web tier | 1 × t3.micro | 7.59 |
| EC2 app tier | 1 × t3.small | 15.18 |
| EBS | 2 × 8 GiB gp3 | 1.28 |
| RDS MySQL | db.t3.micro Single-AZ + 20 GiB gp2 | 14.71 |
| NAT gateway | 1 × NAT + ~10 GB processed | 33.30 |
| Application Load Balancers | public + internal, low LCU usage | 35.86 |
| Public IPv4 addresses | NAT EIP + 2 × ALB + 1 × web instance | 14.60 |
| CloudWatch | 13 alarms, dashboard, detailed monitoring, agent metrics, ~1 GB logs | ≈ 12.00 |
| S3, Secrets Manager, DynamoDB lock table | < 1 GB, 1 secret, on-demand | ≈ 0.60 |
| **Total** | | **≈ $135 / month** (≈ $0.19 / hour) |

Running it only while you work on the project (~32 hours) costs roughly **$6–7**. Multi-AZ RDS adds ≈ $15/month.
See [docs/cost-estimate.md](docs/cost-estimate.md) for the breakdown and savings tips.

## Deploying new releases

Two options:

1. **Terraform** — `terraform apply` re-packages `app/`, uploads it, and because the bundle hash is part of the
   launch template user data, the ASGs perform a rolling instance refresh automatically.
2. **Script (no infra changes)** —

   ```bash
   ./scripts/deploy.sh            # test → package → upload → refresh app + web ASGs → smoke test
   ./scripts/deploy.sh --skip-web --no-wait
   ```

Refreshes use `MinHealthyPercentage=100 / MaxHealthyPercentage=200`, so new instances become healthy
before old ones are terminated (no downtime, even with one instance per tier).

## Destroying the stack

```bash
./scripts/destroy.sh                    # asks you to type the environment name
./scripts/destroy.sh --destroy-backend  # also deletes the state bucket and lock table
```

or simply `cd terraform && terraform destroy`. RDS uses `skip_final_snapshot = true` in dev — data is lost.

## Security notes

- Only the public ALB is reachable from the internet; app instances and RDS live in private subnets and each
  security group only accepts traffic from the tier in front of it.
- No SSH keys needed: use **SSM Session Manager** (`aws ssm start-session --target <instance-id>`). An optional
  bastion (`enable_bastion = true`) only allows SSH from `admin_cidr`.
- DB credentials are generated by Terraform and stored in **Secrets Manager**; they are never placed in
  user data. They *are* present in Terraform state, so keep the encrypted, versioned state bucket private.
- IMDSv2 is enforced, EBS/RDS/S3 are encrypted, S3 buckets block public access and deny non-TLS requests.
- The demo listener is **HTTP only**. For production add an ACM certificate and an HTTPS listener on 443
  (the ALB security group already allows it) and redirect 80 → 443.
- For production also consider: `db_multi_az = true`, one NAT gateway per AZ, `deletion_protection`,
  longer backup retention, AWS WAF on the ALB, and `s3_force_destroy = false`.

## Documentation

| Document | Contents |
|----------|----------|
| [docs/architecture.md](docs/architecture.md) | Diagrams, network layout, security groups, data flow, design decisions |
| [docs/setup-guide.md](docs/setup-guide.md) | Step-by-step installation, configuration, deployment and verification |
| [docs/monitoring.md](docs/monitoring.md) | Alarms, SNS subscriptions, logs, custom metrics, extending monitoring |
| [docs/cost-estimate.md](docs/cost-estimate.md) | Itemised monthly cost and how to reduce it |

## License

Released under the [MIT License](LICENSE).

```
MIT License

Copyright (c) 2026 Christian Gallon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
