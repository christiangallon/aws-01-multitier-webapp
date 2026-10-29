# Architecture

This document describes the infrastructure that Terraform creates, how traffic flows between the tiers,
and why it is designed this way.

## 1. High-level view

```
                                 ┌──────────────┐
                                 │    Users     │
                                 └──────┬───────┘
                                        │ HTTP :80 (HTTPS :443 ready)
┌───────────────────────────────────────┼─────────────────────────────── AWS us-east-1 ───────┐
│                                       │                                                     │
│  ┌────────────────────────────────────┼───────────────────── VPC 10.0.0.0/16 ────────────┐  │
│  │                            ┌───────▼────────┐                                         │  │
│  │                            │ Internet GW    │                                         │  │
│  │                            └───────┬────────┘                                         │  │
│  │   ┌──── us-east-1a ────────────────┼───────────────────── us-east-1b ─────────────┐   │  │
│  │   │                                │                                             │   │  │
│  │   │  PUBLIC 10.0.1.0/24     ┌──────▼───────────────────┐   PUBLIC 10.0.2.0/24    │   │  │
│  │   │                         │  Public ALB  (alb-sg)    │                         │   │  │
│  │   │                         └──────┬────────────┬──────┘                         │   │  │
│  │   │  ┌──────────────┐       ┌──────▼──────┐ ┌───▼─────────┐                      │   │  │
│  │   │  │ NAT Gateway  │       │ web (nginx) │ │ web (nginx) │  Web ASG 1–3         │   │  │
│  │   │  │  + EIP       │       │ t3.micro    │ │ t3.micro    │  (web-sg)            │   │  │
│  │   │  └──────▲───────┘       └──────┬──────┘ └───┬─────────┘                      │   │  │
│  │   │ ........│......................│............│.................................   │  │
│  │   │         │               ┌──────▼────────────▼──────┐                         │   │  │
│  │   │  PRIVATE│10.0.11.0/24   │ Internal ALB :3000       │   PRIVATE 10.0.12.0/24  │   │  │
│  │   │         │               │ (internal-alb-sg)        │                         │   │  │
│  │   │         │               └──────┬────────────┬──────┘                         │   │  │
│  │   │         │               ┌──────▼──────┐ ┌───▼─────────┐                      │   │  │
│  │   │         └───────────────┤ app Node.js │ │ app Node.js │  App ASG 1–3         │   │  │
│  │   │          (npm, updates) │ t3.small    │ │ t3.small    │  (app-sg)            │   │  │
│  │   │                         └──────┬──────┘ └───┬─────────┘                      │   │  │
│  │   │                                └─────┬──────┘                                │   │  │
│  │   │                    ┌─────────────────▼───┐        ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐      │   │  │
│  │   │                    │ RDS MySQL 8.0 primary│ ─sync─   RDS standby (only        │   │  │
│  │   │                    │ db.t3.micro (rds-sg) │        │ if db_multi_az=true) │    │   │  │
│  │   │                    └──────────────────────┘        └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘      │   │  │
│  │   └──────────────────────────────────────────────────────────────────────────────┘   │  │
│  │        S3 gateway endpoint (route tables) ───────────────┐                             │  │
│  └──────────────────────────────────────────────────────────┼─────────────────────────────┘  │
│                                                             ▼                                │
│   ┌──────────────── S3 ────────────────┐   ┌──────────── CloudWatch ─────────────┐           │
│   │ <prefix>-app-artifacts  (app.zip)  │   │ Metrics: EC2, ALB, RDS, CWAgent     │           │
│   │ <prefix>-static-assets  (UI files) │   │ Logs: /aws/ec2/app-tier, web-tier   │           │
│   │ <prefix>-access-logs    (S3 + ALB) │   │ Alarms ──► SNS topic ──► e-mail     │           │
│   └────────────────────────────────────┘   │ Dashboard: <prefix>-overview        │           │
│   ┌──────── Secrets Manager ──────────┐    └─────────────────────────────────────┘           │
│   │ <prefix>/rds/master (credentials) │    IAM: <prefix>-ec2-role (SSM, CW agent, S3, secret) │
│   └───────────────────────────────────┘                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

## 2. Network layout

| Subnet | CIDR | AZ | Route table | Contents |
|--------|------|----|-------------|----------|
| public-1 | `10.0.1.0/24` | us-east-1a | `0.0.0.0/0 → IGW` | Public ALB node, web instances, NAT gateway, optional bastion |
| public-2 | `10.0.2.0/24` | us-east-1b | `0.0.0.0/0 → IGW` | Public ALB node, web instances |
| private-1 | `10.0.11.0/24` | us-east-1a | `0.0.0.0/0 → NAT` | Internal ALB node, app instances, RDS primary |
| private-2 | `10.0.12.0/24` | us-east-1b | `0.0.0.0/0 → NAT` | Internal ALB node, app instances, RDS standby / subnet group |

- DNS support and DNS hostnames are enabled on the VPC (required for RDS endpoints and the VPC resolver used by nginx).
- A single NAT gateway keeps dev cost down. It is a cross-AZ single point of failure for **outbound** traffic only;
  production should use one NAT gateway per AZ.
- An **S3 gateway endpoint** is attached to both route tables, so instance traffic to S3 (bundles, static assets)
  stays on the AWS network and does not incur NAT data-processing charges.

## 3. Security groups

Each tier only accepts traffic from the tier directly in front of it.

| Security group | Inbound | From | Outbound |
|----------------|---------|------|----------|
| `alb-sg` | TCP 80, 443 | `0.0.0.0/0` | all |
| `web-sg` | TCP 80 | `alb-sg` | all |
| | TCP 22 | `bastion-sg` | |
| `internal-alb-sg` | TCP 3000 | `web-sg` | all |
| `app-sg` | TCP 3000 | `web-sg`, `internal-alb-sg` | all |
| | TCP 22 | `bastion-sg` | |
| `rds-sg` | TCP 3306 | `app-sg` | all |
| `bastion-sg` | TCP 22 | `var.admin_cidr` | all |

Rules are defined as standalone `aws_vpc_security_group_ingress_rule` / `egress_rule` resources so groups can
reference each other without dependency cycles.

## 4. Request flow

1. The browser calls `http://<public-alb-dns>/`.
2. The public ALB forwards to a healthy **web** instance (target group health check: `GET /health`).
3. **nginx** serves the static UI (`index.html`, `app.js`, `styles.css`) that it synced from the
   static-assets bucket at boot.
4. Requests to `/api/*`, `/health` and `/ready` are proxied to the **internal ALB** on port 3000. nginx
   re-resolves the ALB's DNS name every 30 s through the VPC resolver (`169.254.169.253`) because ALB IPs change.
5. The internal ALB forwards to a healthy **app** instance (health check `GET /health`).
6. The Express app queries **RDS MySQL** via a `mysql2` connection pool (10 connections per instance).

## 5. Compute details

| | Web tier | App tier |
|---|---|---|
| AMI | Latest Amazon Linux 2023 (SSM public parameter) | same |
| Instance type | `t3.micro` | `t3.small` |
| Subnets | public | private |
| ASG min / desired / max | 1 / 1 / 3 | 1 / 1 / 3 |
| ASG health check | EC2 (an app outage must not recycle nginx) | ELB (unhealthy app instances are replaced) |
| Scaling | Target tracking, average CPU 60 % | same |
| Bootstrap | `web_userdata.sh`: nginx, static sync, CloudWatch agent | `app_userdata.sh`: Node.js 20, bundle from S3, `npm ci`, systemd, CloudWatch agent |
| Launch template | IMDSv2 required (hop limit 2), detailed monitoring, encrypted gp3 root volume | same |

**Releases:** the app bundle's MD5 and the static assets' hash are embedded (as comments) in the user data.
When either changes, Terraform creates a new launch-template version and the ASG's `instance_refresh` block
rolls instances with `min_healthy_percentage = 100` / `max_healthy_percentage = 200` (launch before terminate).
`scripts/deploy.sh` triggers the same rolling refresh without a Terraform run.

## 6. Data tier

- **Engine:** MySQL 8.0 (`db.t3.micro`, 20 GiB gp2, storage autoscaling up to 50 GiB, encrypted at rest).
- **Placement:** DB subnet group spanning both private subnets; `publicly_accessible = false`.
- **Availability:** `db_multi_az` (default `false`) adds a synchronous standby in the second AZ.
- **Parameter group:** `utf8mb4` charset/collation, slow-query log (> 2 s). Error and slow-query logs are exported to CloudWatch Logs.
- **Credentials:** Terraform generates a random password and stores
  `{username, password, host, port, dbname, engine}` in Secrets Manager (`<prefix>/rds/master`).
  App instances read it at service start using their instance role; it is never written into user data.
- **Dev defaults:** `deletion_protection = false`, `skip_final_snapshot = true`, 1-day backups.

## 7. Storage

| Bucket | Purpose | Lifecycle |
|--------|---------|-----------|
| `<prefix>-app-artifacts` | `releases/app.zip` (+ versioned `app-<git-sha>.zip` from deploy.sh) | IA 30 d → Glacier 90 d → expire 365 d; old versions expire after 90 d |
| `<prefix>-static-assets` | Static UI files synced by web instances | Non-current versions: IA 30 d → Glacier 90 d → expire 365 d |
| `<prefix>-access-logs` | S3 server access logs (`s3/`) and ALB access logs (`alb/`) | IA 30 d → Glacier 90 d → expire 365 d |

All buckets: versioning, SSE-S3 (AES-256 with bucket keys), `BucketOwnerEnforced`, full public access block,
and a bucket policy denying non-TLS requests.

> The artifacts lifecycle rule expires objects after 365 days. Terraform re-uploads `releases/app.zip`
> whenever the code changes; if a bundle is untouched for a year, run `terraform apply -replace=aws_s3_object.app_bundle`
> or `scripts/deploy.sh` before scaling out.

## 8. Identity

A single role `<prefix>-ec2-role` (instance profile `<prefix>-ec2-profile`) is attached to both tiers:

- `AmazonSSMManagedInstanceCore` — Session Manager shell access and patching, no SSH keys needed
- `CloudWatchAgentServerPolicy` — publish agent metrics and logs
- Inline policy — `s3:ListBucket`/`s3:GetObject` on the artifacts and static-assets buckets,
  `secretsmanager:GetSecretValue` on the DB secret only, `ec2:DescribeTags`

## 9. Monitoring

See [monitoring.md](monitoring.md). In short: 13 alarms (EC2/ASG, ALB, RDS, CloudWatch-agent memory, log-based
5xx), an SNS topic with optional e-mail subscription, two log groups with 14-day retention, JSON log metric
filters, and a CloudWatch dashboard.

## 10. Design decisions

| Decision | Rationale |
|----------|-----------|
| Internal ALB between web and app tiers | App instances are replaced/scaled by the ASG; the ALB gives nginx a stable endpoint, health checks and load balancing. |
| nginx serves static assets from S3 | Demonstrates a real web tier: static content is served without touching Node.js, while dynamic requests are proxied. |
| Terraform packages and uploads the app | The first `terraform apply` yields a working stack — no chicken-and-egg with an empty artifacts bucket. |
| Secrets Manager instead of tfvars passwords | Credentials never appear in user data, shell history or tfvars files. |
| Single NAT gateway | Saves ≈ $33/month in dev; documented as a production change. |
| SSM instead of SSH | No inbound port 22 or key management required; bastion is optional. |
| Liveness (`/health`) vs readiness (`/ready`) | A brief DB outage should not make the ASG terminate every app instance. |
