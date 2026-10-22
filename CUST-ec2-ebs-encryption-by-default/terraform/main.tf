# ------------------------------------------------------------------------------
# EBS encryption by default (per region)
#
# New volumes and snapshot copies in this region are encrypted automatically.
# Existing volumes/snapshots are NOT changed. Optionally sets a customer-managed
# KMS key as the region default; otherwise the AWS managed key aws/ebs is used.
#
# Destroy: the provider disables encryption-by-default on delete and resets
# the default key to aws/ebs.
# ------------------------------------------------------------------------------

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  count = var.default_kms_key_arn == null ? 0 : 1

  key_arn = var.default_kms_key_arn

  depends_on = [aws_ebs_encryption_by_default.this]
}
