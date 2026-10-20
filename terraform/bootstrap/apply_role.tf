# Write-capable role for terraform-apply.yml.
data "aws_iam_policy_document" "apply_trust" {
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
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${var.github_sub_prefix}:ref:refs/heads/main",
        "${var.github_sub_prefix}:environment:dev-apply",
      ]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "github-actions-apply"
  description          = "GitHub Actions terraform apply (main branch only)"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "apply" {
  # Everything the plan role can read (refresh happens before apply too).
  source_policy_documents = [data.aws_iam_policy_document.plan.json]

  # Most create/tag/describe APIs for these services do not support
  # resource-level scoping at create time.
  statement {
    sid    = "NetworkingAndLoadBalancing"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid    = "EcsRdsLogsAlarmsAcmSns"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeleteCluster",
      "ecs:UpdateCluster",
      "ecs:PutClusterCapacityProviders",
      "ecs:CreateService",
      "ecs:UpdateService",
      "ecs:DeleteService",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DeleteTaskDefinitions",
      "ecs:TagResource",
      "ecs:UntagResource",
      "rds:CreateDBInstance",
      "rds:ModifyDBInstance",
      "rds:DeleteDBInstance",
      "rds:CreateDBSubnetGroup",
      "rds:ModifyDBSubnetGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
      "logs:PutMetricFilter",
      "logs:DeleteMetricFilter",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "acm:ImportCertificate",
      "acm:DeleteCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:TagResource",
      "sns:UntagResource",
      "servicequotas:RequestServiceQuotaIncrease",
      "budgets:CreateBudget",
      "budgets:ModifyBudget",
      "budgets:DeleteBudget",
      "budgets:TagResource",
      "budgets:UntagResource",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region, "us-east-1"] # budgets/servicequotas global endpoints resolve to us-east-1
    }
  }

  # RDS with manage_master_user_password creates an rds!db-* secret and needs
  # KMS via the RDS service only.
  statement {
    sid       = "RdsManagedMasterSecret"
    effect    = "Allow"
    actions   = ["kms:CreateGrant", "kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["arn:aws:kms:${local.region}:${local.account_id}:key/*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["rds.${local.region}.amazonaws.com", "secretsmanager.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid    = "ServiceLinkedRoles"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }
  }

  # Secrets: only ai-* names, including PutResourcePolicy for the existing
  # gateway-key / Langfuse-key / app-key resource policies.
  statement {
    sid    = "ManageOwnSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:UpdateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:RestoreSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:DeleteResourcePolicy",
      "secretsmanager:ValidateResourcePolicy",
    ]
    resources = ["arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:ai-*"]
  }

  # IAM: roles/policies named ai-* only. github-actions-* and the OIDC
  # provider are out of reach, so this role cannot alter its own permissions.
  statement {
    sid    = "ManageOwnRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/ai-*"]
  }

  # Attaching is limited to the one AWS-managed policy the ECS execution
  # role uses.
  statement {
    sid       = "AttachOnlyEcsExecutionPolicy"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = ["arn:aws:iam::${local.account_id}:role/ai-*"]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
    }
  }

  statement {
    sid       = "PassGatewayRolesToEcs"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/ai-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Only the gateway's ALB access-log bucket, not s3:* and not any other bucket.
  statement {
    sid    = "ManageAlbLogBucket"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketTagging",
    ]
    resources = ["arn:aws:s3:::ai-gateway-advisor-chat-alb-logs-${local.account_id}"]
  }

  # Only web ACLs named ai-gateway-*, associated only with the gateway ALB.
  statement {
    sid    = "ManageGatewayWaf"
    effect = "Allow"
    actions = [
      "wafv2:CreateWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:TagResource",
      "wafv2:UntagResource",
      "wafv2:CreateIPSet",
      "wafv2:UpdateIPSet",
      "wafv2:DeleteIPSet",
    ]
    resources = [
      "arn:aws:wafv2:${local.region}:${local.account_id}:regional/webacl/ai-gateway-*/*",
      "arn:aws:wafv2:${local.region}:${local.account_id}:regional/ipset/ai-gateway-*/*",
      "arn:aws:elasticloadbalancing:${local.region}:${local.account_id}:loadbalancer/app/ai-gateway-*/*",
    ]
  }

  statement {
    sid       = "AttachWebAclToAlb"
    effect    = "Allow"
    actions   = ["elasticloadbalancing:SetWebAcl"]
    resources = ["arn:aws:elasticloadbalancing:${local.region}:${local.account_id}:loadbalancer/app/ai-gateway-*/*"]
  }

  statement {
    sid       = "WriteState"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/dev/*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
