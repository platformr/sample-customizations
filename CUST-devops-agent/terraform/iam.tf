# ------------------------------------------------------------------------------
# IAM roles for AWS DevOps Agent (mirrors the "IAM roles setup" section of the
# AWS DevOps Agent CLI onboarding guide).
# ------------------------------------------------------------------------------

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # Confused-deputy scoping: only agent spaces in THIS account+region may assume.
  agent_space_source_arn = "arn:${local.partition}:aidevops:${local.region}:${local.account_id}:agentspace/*"
}

# ---- 1. Agent space role (topology discovery / investigations) ---------------

data "aws_iam_policy_document" "agent_space_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.agent_space_source_arn]
    }
  }
}

resource "aws_iam_role" "agent_space" {
  name               = var.agent_space_role_name
  description        = "Assumed by AWS DevOps Agent agent spaces to inspect this account."
  assume_role_policy = data.aws_iam_policy_document.agent_space_trust.json
}

resource "aws_iam_role_policy_attachment" "agent_space_access" {
  role       = aws_iam_role.agent_space.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

# The agent uses Resource Explorer for topology discovery and needs to be able
# to create its service-linked role on first use.
data "aws_iam_policy_document" "agent_space_slr" {
  statement {
    sid     = "AllowCreateServiceLinkedRoles"
    effect  = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer",
    ]
  }
}

resource "aws_iam_role_policy" "agent_space_slr" {
  name   = "AllowCreateServiceLinkedRoles"
  role   = aws_iam_role.agent_space.id
  policy = data.aws_iam_policy_document.agent_space_slr.json
}

# ---- 2. Operator app role (IAM auth flow for the web app) --------------------

data "aws_iam_policy_document" "operator_app_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.agent_space_source_arn]
    }
  }
}

resource "aws_iam_role" "operator_app" {
  name               = var.operator_app_role_name
  description        = "Assumed by the AWS DevOps Agent operator web app (IAM auth flow)."
  assume_role_policy = data.aws_iam_policy_document.operator_app_trust.json
}

resource "aws_iam_role_policy_attachment" "operator_app_access" {
  role       = aws_iam_role.operator_app.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
}
