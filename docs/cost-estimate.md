# Cost Estimate

Estimated monthly cost of the **dev** configuration (`terraform.tfvars.example` defaults) in **us-east-1**,
using on-demand list prices, 730 hours/month and light traffic.

> ⚠️ **These are estimates, not quotes.** AWS prices change and depend on usage. Always confirm with the
> [AWS Pricing Calculator](https://calculator.aws/) and watch **Billing → Cost Explorer**. Free Tier
> credits/allowances (if your account has them) reduce the totals.

## 1. Itemised monthly estimate

| # | Service | Resource | Unit price (approx.) | Quantity | ≈ USD / month |
|---|---------|----------|----------------------|----------|--------------:|
| 1 | EC2 | Web tier `t3.micro` | $0.0104 / h | 1 × 730 h | 7.59 |
| 2 | EC2 | App tier `t3.small` | $0.0208 / h | 1 × 730 h | 15.18 |
| 3 | EBS | gp3 root volumes | $0.08 / GB-month | 2 × 8 GB | 1.28 |
| 4 | RDS | MySQL `db.t3.micro` Single-AZ | $0.017 / h | 730 h | 12.41 |
| 5 | RDS | gp2 storage | $0.115 / GB-month | 20 GB | 2.30 |
| 6 | RDS | Automated backups (1 day) | free up to DB size | — | 0.00 |
| 7 | VPC | NAT gateway | $0.045 / h | 730 h | 32.85 |
| 8 | VPC | NAT data processing | $0.045 / GB | ~10 GB (packages, updates) | 0.45 |
| 9 | ELB | Public ALB | $0.0225 / h | 730 h | 16.43 |
| 10 | ELB | Public ALB LCUs | $0.008 / LCU-h | low traffic | ≈ 1.50 |
| 11 | ELB | Internal ALB | $0.0225 / h | 730 h | 16.43 |
| 12 | ELB | Internal ALB LCUs | $0.008 / LCU-h | low traffic | ≈ 1.50 |
| 13 | VPC | Public IPv4 addresses | $0.005 / h each | 4 (NAT EIP, 2 × ALB, 1 × web) | 14.60 |
| 14 | CloudWatch | Alarms (standard) | $0.10 / alarm | 13 (+ 4 target-tracking) | 1.70 |
| 15 | CloudWatch | Dashboard | $3.00 / dashboard (first 3 free) | 1 | 0.00 – 3.00 |
| 16 | CloudWatch | Detailed monitoring | ≈ $2.10 / instance | 2 | 4.20 |
| 17 | CloudWatch | Custom metrics (agent + filters) | $0.30 / metric | ~10 | 3.00 |
| 18 | CloudWatch | Logs ingestion + storage | $0.50 / GB ingested | ~1 GB | 0.53 |
| 19 | S3 | 3 buckets + state bucket | $0.023 / GB-month + requests | < 1 GB | ≈ 0.10 |
| 20 | Secrets Manager | DB secret | $0.40 / secret | 1 | 0.40 |
| 21 | DynamoDB | State lock table (on-demand) | per request | negligible | ≈ 0.00 |
| 22 | Data transfer | Internet egress | first 100 GB/month free | light | 0.00 |
| | | | | **Total (dev)** | **≈ $132 – $136** |

**Hourly:** ≈ $0.18–0.19 / hour while the stack is running.

## 2. Cost by tier

| Tier | Components | ≈ USD / month | Share |
|------|------------|--------------:|------:|
| Networking | NAT gateway, public IPv4 | 47.90 | 36 % |
| Load balancing | 2 ALBs + LCUs | 35.86 | 27 % |
| Compute | 2 EC2 + EBS | 24.05 | 18 % |
| Database | RDS instance + storage | 14.71 | 11 % |
| Monitoring | CloudWatch | ≈ 9.40 – 12.40 | 8 % |
| Storage & secrets | S3, Secrets Manager, DynamoDB | ≈ 0.50 | < 1 % |

The "plumbing" (NAT gateway, public IPs, load balancers) costs more than the servers themselves; this is
typical for small multi-tier deployments.

## 3. Lab-session cost

This is a 24–32 hour project. If you **destroy the stack between sessions**:

| Usage pattern | ≈ Cost |
|---------------|-------:|
| 32 hours of total runtime | $6 – $7 |
| 8 h/day, 5 days/week for a month (~175 h) | $33 |
| Left running 24×7 for a month | $135 |

`terraform apply` takes ~15–20 minutes and `destroy` ~10–15 minutes, so tearing down overnight is practical.
The state backend (S3 + DynamoDB) costs pennies and can be kept.

## 4. Production-like configuration

| Change | ≈ Additional USD / month |
|--------|-------------------------:|
| `db_multi_az = true` (standby + doubled storage) | + 14.71 |
| Second NAT gateway (one per AZ) + EIP | + 36.50 |
| Desired capacity 2 per tier (one per AZ) | + 24.05 |
| `db.t3.small` instead of `db.t3.micro` | + 12.41 (Single-AZ) |
| 7-day backups | storage beyond DB size at $0.095 / GB-month |
| AWS WAF on the public ALB (1 web ACL + 5 rules) | + 10.00 + $0.60 / million requests |
| **Typical small production total** | **≈ $230 – $260** |

## 5. Ways to reduce dev cost

| Option | Saving / month | Trade-off |
|--------|---------------:|-----------|
| Destroy when not in use | up to 100 % | 15–20 min to re-create |
| Disable detailed monitoring (`monitoring.enabled = false` in launch templates) | ≈ 4.20 | 5-minute EC2 metrics; alarms react slower |
| Use `t3.micro` for the app tier | ≈ 7.59 | 1 GiB RAM; fine for the demo app |
| Run nginx and Node.js on the same instances and drop the internal ALB | ≈ 18 | No longer a separate app tier |
| Replace NAT gateway with VPC endpoints only (S3 already free) + pre-baked AMI | ≈ 33 | No internet egress from private subnets; requires building an AMI with Node.js and dependencies |
| Free Tier account (first 12 months, legacy plan) | t3.micro / db.t3.micro hours, 30 GB EBS, 20 GB RDS | Only one instance of each fits in the 750 h allowance |
| Reserved Instances / Savings Plans | 30–40 % on EC2/RDS | 1- or 3-year commitment — not worth it for a lab |

## 6. Keeping an eye on spend

```bash
# Month-to-date cost by service
aws ce get-cost-and-usage \
  --time-period Start=$(date -u +%Y-%m-01),End=$(date -u -d tomorrow +%Y-%m-%d) \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[?Metrics.UnblendedCost.Amount>`0.01`].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output table
```

Create an **AWS Budget** (e.g. $25/month with 80 % and 100 % e-mail alerts) in *Billing → Budgets* so a
forgotten stack never surprises you. All resources are tagged `Project`, `Environment` and `ManagedBy` —
activate them as *cost allocation tags* to filter Cost Explorer by project.
