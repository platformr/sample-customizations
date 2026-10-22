# ------------------------------------------------------------------------------
# Amazon Bedrock model enablement (Anthropic Claude)
#
# Since late 2025, serverless Bedrock models auto-enable on first invocation
# when the caller has AWS Marketplace permissions. This customization makes the
# enablement explicit and reviewable instead of relying on first use:
#
#   1. aws_bedrock_use_case_for_model_access  -> PutUseCaseForModelAccess
#      (one-time Anthropic first-time-user form, account/org level)
#   2. data aws_bedrock_foundation_model_agreement_offers -> offer token
#   3. aws_bedrock_foundation_model_agreement -> CreateFoundationModelAgreement
#      (one per model; this is the Marketplace subscription/EULA acceptance)
#
# Validation of the resulting access status (GetFoundationModelAvailability)
# happens in post-api-helpers.sh.
# ------------------------------------------------------------------------------

resource "aws_bedrock_use_case_for_model_access" "anthropic" {
  count = var.submit_use_case_form ? 1 : 0

  form_data = jsonencode({
    companyName         = var.use_case_company_name
    companyWebsite      = var.use_case_company_website
    intendedUsers       = var.use_case_intended_users
    industryOption      = var.use_case_industry
    otherIndustryOption = ""
    useCases            = var.use_case_description
  })
}

data "aws_bedrock_foundation_model_agreement_offers" "model" {
  for_each = toset(var.model_ids)

  model_id   = each.value
  offer_type = "PUBLIC"
}

resource "aws_bedrock_foundation_model_agreement" "model" {
  for_each = toset(var.model_ids)

  model_id    = each.value
  offer_token = data.aws_bedrock_foundation_model_agreement_offers.model[each.value].offers[0].offer_token

  # Offer tokens rotate; the agreement itself does not need replacing.
  lifecycle {
    ignore_changes = [offer_token]
  }

  depends_on = [aws_bedrock_use_case_for_model_access.anthropic]
}

# Hand-off for post-api-helpers.sh: which models to check.
resource "aws_ssm_parameter" "model_ids" {
  name        = "/platformr/${var.customization_name}/model_ids"
  description = "Published by ${var.customization_name} for api_helpers."
  type        = "StringList"
  value       = join(",", var.model_ids)
}

# Hand-off for post-api-helpers.sh: desired data retention mode ("unset" = leave alone).
resource "aws_ssm_parameter" "data_retention_mode" {
  name        = "/platformr/${var.customization_name}/data_retention_mode"
  description = "Published by ${var.customization_name} for api_helpers."
  type        = "String"
  value       = coalesce(var.data_retention_mode, "unset")
}
