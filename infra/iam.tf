###############################################################################
# IAM for EC2 instances.
#
# Each instance assumes this role at boot. It grants:
#   - SSM Session Manager so we can shell into private instances without a
#     bastion or SSH keys (audited, cheap, zero ports open).
#   - CloudWatch Agent permissions for metrics + logs.
#   - Read access to the one DB credentials secret.
#
# Principle of least privilege: secret access is scoped to a single ARN, not
# secretsmanager:* on *.
###############################################################################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_instance" {
  name_prefix        = "${local.name_prefix}-app-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "secret_read" {
  statement {
    sid     = "ReadDbSecret"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.db.arn,
    ]
  }
}

resource "aws_iam_role_policy" "secret_read" {
  name   = "secret-read"
  role   = aws_iam_role.app_instance.id
  policy = data.aws_iam_policy_document.secret_read.json
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "${local.name_prefix}-app-"
  role        = aws_iam_role.app_instance.name
}
