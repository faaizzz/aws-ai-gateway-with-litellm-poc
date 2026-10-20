# Read-only role for terraform.yml's `plan` job and drift-detection.yml.
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.github_sub_prefix}:*"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "github-actions-plan"
  description          = "GitHub Actions terraform plan / drift detection (read-only)"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "plan" {
  # Refresh needs to read every service terraform/environments/dev manages.
  statement {
    sid    = "ReadManagedServices"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "elasticloadbalancing:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "iam:Get*",
      "iam:List*",
      "rds:Describe*",
      "rds:ListTagsForResource",
      "logs:Describe*",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
      "cloudwatch:Describe*",
      "cloudwatch:List*",
      "servicequotas:Get*",
      "servicequotas:List*",
      "budgets:Describe*",
      "budgets:ViewBudget",
      "budgets:ListTagsForResource",
      "sns:Get*",
      "sns:List*",
      "acm:Describe*",
      "acm:Get*",
      "acm:List*",
      "kms:DescribeKey",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReadSecretMetadata"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:ListSecrets",
    ]
    resources = ["*"]
  }

  # aws_secretsmanager_secret_version refresh reads the value;
  statement {
    sid       = "ReadOwnSecretValues"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:ai-*"]
  }

  # Refresh of the gateway's ALB access-log bucket (llm-gateway/alb_logs.tf).
  statement {
    sid    = "ReadAlbLogBucketConfig"
    effect = "Allow"
    actions = [
      "s3:GetBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketOwnershipControls",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketLogging",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetBucketWebsite",
      "s3:GetAccelerateConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = ["arn:aws:s3:::ai-gateway-advisor-chat-alb-logs-${local.account_id}"]
  }

  # Refresh of the gateway's WAF web ACL (llm-gateway/waf.tf).
  statement {
    sid    = "ReadWaf"
    effect = "Allow"
    actions = [
      "wafv2:GetWebACL",
      "wafv2:ListTagsForResource",
      "wafv2:GetWebACLForResource",
      "wafv2:ListWebACLs",
      "wafv2:GetIPSet",
      "wafv2:ListIPSets",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/dev/*"]
  }

  # DEVIATION from "no put/delete anywhere": -native state locking creates
  # and deletes `<key>.tflock` for every plan that takes the lock, so a plan
  # cannot run without it.
  statement {
    sid       = "StateLockFileOnly"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/dev/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan-read-only"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}
