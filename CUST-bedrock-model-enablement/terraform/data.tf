# Account / region context. Prefer these over hard-coding IDs so the same
# customization can be deployed to any target account.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
