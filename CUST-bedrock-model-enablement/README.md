# CUST-bedrock-model-enablement

> Enable access to Anthropic Claude models on Amazon Bedrock for the account:
> submit the one-time Anthropic use-case form and create foundation-model
> agreements for Claude Fable 5.1 and Claude Opus 5.5 (us-east-1).

## What it does

Amazon Bedrock now auto-enables most serverless models on first invocation,
but that relies on whichever principal happens to call first having
Marketplace permissions, and Anthropic models additionally need a one-time
use-case form. This customization does both steps explicitly so model access
is set up, reviewable and reproducible before any workload runs:

1. **Anthropic first-time use-case form** (`PutUseCaseForModelAccess`), once
   per account. If the Organizations management account already submitted
   it, set `submit_use_case_form = false`.
2. **Foundation-model agreement** (`CreateFoundationModelAgreement`) for each
   base model ID in `var.model_ids`. This is the Marketplace subscription and
   EULA acceptance. Defaults:

| Model | Base model ID | Marketplace product ID | Inference profile IDs |
| --- | --- | --- | --- |
| Claude Fable 5.1 | `anthropic.claude-fable-5-1` | `prod-lt3y75wunrtv4` | `us.anthropic.claude-fable-5-1`, `global.anthropic.claude-fable-5-1` |
| Claude Opus 5.5 | `anthropic.claude-opus-5-5` | `prod-e5xo6z26ie45g` | `us.anthropic.claude-opus-5-5`, `global.anthropic.claude-opus-5-5`, plus `eu.`/`au.`/`jp.` |

Neither model offers in-region inference from `us-east-1`; applications
invoke them through the `us.` or `global.` inference profile ID. The
agreement is per account, not per region.

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/main.tf` | `aws_bedrock_use_case_for_model_access`, `data.aws_bedrock_foundation_model_agreement_offers`, `aws_bedrock_foundation_model_agreement` (for_each), SSM hand-off of model IDs |
| `api_helpers/pre-api-helpers.sh` | Checks the CLI version; reports whether the use-case form is already on file |
| `api_helpers/post-api-helpers.sh` | Sets the data retention mode (`put-account-data-retention`) if requested; `get-foundation-model-availability` per model: agreement, authorization, entitlement, region availability |

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Region to call the Bedrock control plane in. |
| `model_ids` | Fable 5.1, Opus 5.5 | Base model IDs (no `us.`/`global.` prefix). |
| `submit_use_case_form` | `true` | Set `false` if the org management account already submitted it. |
| `use_case_company_name` | `Example Corp` | **Change this.** |
| `use_case_company_website` | `https://www.example.com` | **Change this.** |
| `use_case_intended_users` | `"0"` | `0` internal, `1` external, `2` both. |
| `use_case_industry` | `Technology` | |
| `use_case_description` | (sample text) | Describe the actual use cases. |
| `data_retention_mode` | `aws_review` | `none`, `default`, `aws_review` or `null` (leave untouched). Required `aws_review` for Fable 5.x. Applied by the post helper. |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `CUSTOMIZATION_NAME` | `CUST-bedrock-model-enablement` | SSM path prefix. |
| `MODEL_IDS` | (from SSM) | Comma-separated fallback if the SSM parameter is missing. |

## Permissions required by the deployment role

```
bedrock:ListFoundationModelAgreementOffers, bedrock:CreateFoundationModelAgreement,
bedrock:DeleteFoundationModelAgreement, bedrock:GetFoundationModelAvailability,
bedrock:PutUseCaseForModelAccess, bedrock:GetUseCaseForModelAccess,
bedrock:GetAccountDataRetention, bedrock:PutAccountDataRetention,
aws-marketplace:Subscribe, aws-marketplace:Unsubscribe, aws-marketplace:ViewSubscriptions,
ssm:PutParameter, ssm:GetParameter, ssm:DeleteParameter, ssm:AddTagsToResource, ssm:ListTagsForResource
```

`aws-marketplace:Subscribe` can be scoped with the `aws-marketplace:ProductId`
condition key to the two product IDs above. The account also needs a valid
payment method for Marketplace.

## Caveats

- **Claude Fable 5.1 data retention.** Fable 5 / 5.1 can only be invoked
  when the account's (per-region) Bedrock data retention mode is
  `aws_review`: prompts and outputs are retained inside AWS for up to 30
  days and may be human-reviewed by AWS (never shared with Anthropic). There
  is no Terraform resource, so the post helper calls
  `bedrock put-account-data-retention --mode aws_review` when
  `var.data_retention_mode` is set (default `aws_review`). Set it to `null`
  to leave the account's setting alone, in which case Fable stays
  unavailable until someone sets it. Organizations can pin the mode with an
  SCP on `bedrock:PutAccountDataRetention`.
- **Agreements re-create themselves.** Deleting an agreement does not block
  access: the next invocation re-subscribes automatically. To actually block
  a model, deny `bedrock:InvokeModel` on its ARN via IAM or an SCP.
- **The use-case form cannot be deleted.** `terraform destroy` only removes it
  from state. Re-applying with different form values errors because the API
  has no update.
- **PENDING agreements.** Right after apply, `agreementAvailability` may be
  `PENDING`; invocations return `AccessDeniedException` until it is
  `AVAILABLE`. AWS emails when it completes.
- **GovCloud.** Third-party model access must be enabled in the linked
  commercial account as well; not covered here.

## Validation

```
[INFO] Model anthropic.claude-fable-5-1:
[ OK ]   agreementAvailability: AVAILABLE
[ OK ]   authorizationStatus: AUTHORIZED
[ OK ]   entitlementAvailability: AVAILABLE
[ OK ]   regionAvailability: AVAILABLE
[INFO] Model anthropic.claude-opus-5-5:
...
[ OK ] Data retention mode (us-east-1): aws_review
```

## Destroy behaviour

`terraform destroy` deletes each foundation-model agreement and the SSM
parameters, and drops the use-case form from state (it stays on file with
AWS). The data retention mode is deliberately left as-is. The post helper
reports each model's agreement status and reminds that invocation re-creates
access.

## Build image requirement

The bedrock model-access CLI commands need AWS CLI v2 >= 2.27.42. Terraform
does not depend on the CLI; only the helpers do, and they skip with a warning
on older CLIs.

## References

- [Request access to Amazon Bedrock foundation models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html)
- [Claude Fable 5.1 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-fable-5-1.html)
- [Claude Opus 5.5 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-5-5.html)
- [Amazon Bedrock data retention](https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html)
- [Amazon Bedrock abuse detection](https://docs.aws.amazon.com/bedrock/latest/userguide/abuse-detection.html)
- Terraform: [`aws_bedrock_foundation_model_agreement`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrock_foundation_model_agreement),
  [`aws_bedrock_use_case_for_model_access`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrock_use_case_for_model_access),
  [`aws_bedrock_foundation_model_agreement_offers`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/bedrock_foundation_model_agreement_offers)
