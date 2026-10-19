data "aws_availability_zones" "available" { state = "available" }
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners = ["amazon"]
  filter { name = "name", values = ["al2023-ami-2023.*-x86_64"] }
  filter { name = "virtualization-type", values = ["hvm"] }
}
resource "random_id" "suffix" { byte_length = 4 }
locals { name = var.project }
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "${local.name}-vpc" }
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.name}-igw" }
}
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-public" }
}
resource "aws_subnet" "private_a" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = { Name = "${local.name}-private-a" }
}
resource "aws_subnet" "private_b" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = { Name = "${local.name}-private-b" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route { cidr_block = "0.0.0.0/0", gateway_id = aws_internet_gateway.main.id }
}
resource "aws_route_table_association" "public" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
resource "aws_security_group" "web" {
  name_prefix = "${local.name}-web-"
  vpc_id = aws_vpc.main.id
  ingress { description = "HTTP demo", from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  egress { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_security_group" "db" {
  name_prefix = "${local.name}-db-"
  vpc_id = aws_vpc.main.id
  ingress { description = "MySQL from web tier", from_port = 3306, to_port = 3306, protocol = "tcp", security_groups = [aws_security_group.web.id] }
  egress { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_db_subnet_group" "main" {
  name = "${local.name}-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}
resource "aws_db_instance" "mysql" {
  identifier = "${local.name}-mysql"
  engine = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"
  allocated_storage = 20
  db_name = "appdb"
  username = var.db_username
  password = var.db_password
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible = false
  storage_encrypted = true
  backup_retention_period = 0
  skip_final_snapshot = true
  deletion_protection = false
  multi_az = false
  tags = { Project = local.name }
}
resource "aws_s3_bucket" "assets" {
  bucket = "${local.name}-${random_id.suffix.hex}"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_iam_role" "ec2" {
  name = "${local.name}-ec2-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "assets" {
  name = "assets-read-write"
  role = aws_iam_role.ec2.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${aws_s3_bucket.assets.arn}/*" }] })
}
resource "aws_iam_instance_profile" "web" {
  name = "${local.name}-profile"
  role = aws_iam_role.ec2.name
}
resource "aws_instance" "web" {
  ami = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile = aws_iam_instance_profile.web.name
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    db_host = aws_db_instance.mysql.address
    db_user = var.db_username
    db_password = var.db_password
    bucket = aws_s3_bucket.assets.bucket
    region = var.aws_region
  })
  user_data_replace_on_change = true
  metadata_options { http_tokens = "required" }
  root_block_device { encrypted = true, volume_size = 12 }
  tags = { Name = "${local.name}-web" }
  depends_on = [aws_route_table_association.public]
}
resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name = "${local.name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 2
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = 300
  statistic = "Average"
  threshold = 70
  alarm_description = "EC2 CPU above 70 percent for two periods"
  dimensions = { InstanceId = aws_instance.web.id }
  alarm_actions = var.alert_email == "" ? [] : [aws_sns_topic.alerts[0].arn]
}
resource "aws_sns_topic" "alerts" {
  count = var.alert_email == "" ? 0 : 1
  name = "${local.name}-alerts"
}
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol = "email"
  endpoint = var.alert_email
}
