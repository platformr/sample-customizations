# ------------------------------------------------------------------------------
# CloudWatch Transaction Search
#
# Account/region-level enablement. This is the one-time prerequisite for:
#   * X-Ray Transaction Search (span search, Application Signals)
#   * Bedrock AgentCore observability (GenAI Observability dashboard, agent
#     traces/spans delivered to CloudWatch Logs)
#
# Mirrors the three API calls in the AWS docs:
#   1. logs:PutResourcePolicy      -> aws_cloudwatch_log_resource_policy
#   2. xray:UpdateTraceSegmentDestination -> aws_xray_trace_segment_destination
#   3. xray:UpdateIndexingRule     -> aws_xray_indexing_rule
# ------------------------------------------------------------------------------

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  spans_log_group_arn       = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:aws/spans:*"
  app_signals_log_group_arn = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/application-signals/data:*"
}

# 1. Allow the X-Ray service to write spans into the two CloudWatch Logs groups
#    that Transaction Search uses. Confused-deputy conditions scope it to this
#    account/region.
data "aws_iam_policy_document" "transaction_search" {
  statement {
    sid    = "TransactionSearchXRayAccess"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["xray.amazonaws.com"]
    }

    actions = ["logs:PutLogEvents"]

    resources = [
      local.spans_log_group_arn,
      local.app_signals_log_group_arn,
    ]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:xray:${local.region}:${local.account_id}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "transaction_search" {
  policy_name     = var.logs_resource_policy_name
  policy_document = data.aws_iam_policy_document.transaction_search.json
}

# 2. Switch span ingestion from X-Ray native storage to CloudWatch Logs.
#    NOTE: deleting this resource does NOT revert the setting (provider docs).
#    post-api-helpers.sh reverts it to "XRay" on destroy.
resource "aws_xray_trace_segment_destination" "this" {
  destination = "CloudWatchLogs"

  depends_on = [aws_cloudwatch_log_resource_policy.transaction_search]
}

# 3. How many spans to index as trace summaries. The rule is always named
#    "Default" and always exists; this resource only updates it.
resource "aws_xray_indexing_rule" "default" {
  name = "Default"

  rule {
    probabilistic {
      desired_sampling_percentage = var.indexing_percentage
    }
  }

  depends_on = [aws_xray_trace_segment_destination.this]
}
