###############################################################################
# IAM role + instance profile shared by the web and app tiers:
#   - AmazonSSMManagedInstanceCore  (Session Manager, no SSH needed)
#   - CloudWatchAgentServerPolicy   (metrics + logs from the CloudWatch agent)
#   - S3 read on the app-artifacts and static-assets buckets
#   - Read of the DB credentials secret
###############################################################################

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.name_prefix}-ec2-role"
  description        = "Instance role for ${var.name_prefix} web and app tiers"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "app_access" {
  statement {
    sid       = "ListAppBuckets"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.artifacts_bucket_arn, var.static_assets_bucket_arn]
  }

  statement {
    sid     = "ReadAppObjects"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = [
      "${var.artifacts_bucket_arn}/*",
      "${var.static_assets_bucket_arn}/*",
    ]
  }

  statement {
    sid       = "ReadDbSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [var.db_secret_arn]
  }

  statement {
    sid       = "DescribeOwnTags"
    effect    = "Allow"
    actions   = ["ec2:DescribeTags", "autoscaling:DescribeAutoScalingInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "app_access" {
  name   = "${var.name_prefix}-app-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.app_access.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}
