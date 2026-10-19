# AWS Multi-Tier Web App
Terraform-built AWS demo with a public EC2 Python API, private MySQL RDS, private S3 storage and a CloudWatch CPU alarm.# 

# AWS Architecture

![AWS Multi-Tier Web Application Architecture](docs/architecture.png)

## Architecture
Browser → Internet Gateway → public EC2 → private RDS / private S3 via AWS API; CloudWatch monitors EC2 CPU.
Two private subnets in different Availability Zones support the RDS subnet group. This is **not** a production HA deployment.

## Prerequisites
Terraform >=1.5, AWS provider permissions for VPC, EC2, RDS, IAM, S3, CloudWatch, optionally SNS. KodeKloud playground may block services or expire before deployment completes.

## Deploy
```bash
cd terraform
export TF_VAR_db_password='REPLACE_WITH_STRONG_RANDOM_PASSWORD'
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output web_url
```
Use an ephemeral, unique password. Never commit state, plans, shell history secrets or screenshots of credentials. Terraform state and EC2 user data **contain the DB password**. This lab uses them for simplicity; production should use Secrets Manager with rotation and private application tiers.

## Test
```bash
URL=$(terraform output -raw web_url)
curl "$URL/"
curl "$URL/health"
curl "$URL/db"
curl "$URL/s3"
```
EC2 bootstrapping can take several minutes after `apply` completes. `/db` confirms MySQL connectivity; `/s3` writes and reads a private S3 object. If errors persist, inspect `/var/log/cloud-init-output.log` via approved playground access/SSM.

## Destroy
```bash
terraform destroy
```
Always destroy before playground expiration. If the playground expires first, the state may be lost and resources may be harder to clean up.

## Security and limits
- HTTP only; do not send sensitive data to this demo.
- Public single EC2 and no load balancer or autoscaling.
- RDS private, encrypted, single-AZ, no retained backups; unsuitable for production.
- S3 public access blocked, versioning and SSE-S3 enabled.
- CPU alarm only; optional SNS email alert requires subscription confirmation.
- S3 and package downloads use outbound public networking; no NAT gateway is needed for RDS.
- IAM role creation, RDS and some instance types may be restricted in KodeKloud.
- AWS resources may incur costs outside an included playground.

## Evidence to capture
`terraform validate`, plan summary (no secrets), working `/health`, `/db`, `/s3`, CloudWatch alarm, VPC subnet view, GitHub README. Never share credentials or sensitive Terraform state.
