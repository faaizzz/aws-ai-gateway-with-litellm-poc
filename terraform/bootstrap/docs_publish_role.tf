# Publish role for docs-publish.yml: writes the docs bucket and invalidates
# the one distribution, from main only.
data "aws_iam_policy_document" "docs_trust" {
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
      values   = ["${var.github_sub_prefix}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "docs" {
  name                 = "github-actions-docs"
  description          = "GitHub Actions docs-publish.yml (main branch only)"
  assume_role_policy   = data.aws_iam_policy_document.docs_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "docs" {
  statement {
    sid       = "ListDocsBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.docs.arn]
  }

  statement {
    sid       = "WriteDocsObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.docs.arn}/*"]
  }

  statement {
    sid       = "InvalidateDocsDistribution"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.docs.arn]
  }
}

resource "aws_iam_role_policy" "docs" {
  name   = "docs-publish"
  role   = aws_iam_role.docs.id
  policy = data.aws_iam_policy_document.docs.json
}
