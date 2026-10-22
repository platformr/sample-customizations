# CUST-transaction-search

> Enable CloudWatch Transaction Search in the target account/region. This is
> the account-level prerequisite for **X-Ray Transaction Search**,
> **Application Signals**, and **Bedrock AgentCore observability** (the
> CloudWatch GenAI Observability dashboard and agent traces/spans).

The X-Ray and Bedrock AgentCore docs describe the same three API calls, so
the two use-cases are one customization.

## What it does

- Adds an account-level CloudWatch Logs resource policy that lets
  `xray.amazonaws.com` write to the `aws/spans` and
  `/aws/application-signals/data` log groups (scoped to this account/region).
- Switches the X-Ray trace segment destination to `CloudWatchLogs`
  (`UpdateTraceSegmentDestination`). From this point all spans sent through
  X-Ray are ingested as structured logs in cost-effective collection mode.
- Sets the `Default` indexing rule to `var.indexing_percentage` (default 1%,
  which is free).
- **Optional**: configures vended log + trace delivery for Bedrock AgentCore
  memory/gateway resources listed in `var.agentcore_log_delivery`.

Transaction Search is per-region. Deploy this customization once per region
you want it in.

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/main.tf` | `aws_cloudwatch_log_resource_policy`, `aws_xray_trace_segment_destination`, `aws_xray_indexing_rule` |
| `terraform/agentcore.tf` | Optional `aws_cloudwatch_log_group` + `aws_cloudwatch_log_delivery_source/destination/delivery` per AgentCore resource |
| `api_helpers/pre-api-helpers.sh` | Context only: logs the current destination so the build shows before/after |
| `api_helpers/post-api-helpers.sh` | Validates (bash), runs the python validator, and on `destroy` reverts the destination to `XRay` |
| `api_helpers/python/validate_transaction_search.py` | boto3 checks: destination status, desired vs actual indexing %, policy principal, `aws/spans` log group presence |

Why both bash and python validators? To show both patterns. The bash checks
cover the simple "is the setting what we asked for" cases with
`aws --query`; the python script does the parts that are clumsy in JMESPath
(parsing the policy document, pagination).

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Region to enable Transaction Search in. |
| `indexing_percentage` | `1` | Percent of spans indexed as trace summaries (0–100). >1% is billable. |
| `logs_resource_policy_name` | `TransactionSearchAccess` | Name of the Logs resource policy. Max 10 account-scoped policies per region. |
| `agentcore_log_delivery` | `{}` | Map of `short-id => AgentCore resource ARN` for vended log/trace delivery. |
| `agentcore_log_retention_days` | `30` | Retention for vended AgentCore log groups. |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `REVERT_TRANSACTION_SEARCH_ON_DESTROY` | `true` | Set `false` to leave Transaction Search on after destroy. |
| `TRANSACTION_SEARCH_POLICY_NAME` | `TransactionSearchAccess` | Must match `logs_resource_policy_name` if you change it. |

## Permissions required by the deployment role

From the AWS prerequisites plus what the helpers call:

```
xray:GetTraceSegmentDestination, xray:UpdateTraceSegmentDestination,
xray:GetIndexingRules, xray:UpdateIndexingRule,
logs:PutResourcePolicy, logs:DeleteResourcePolicy, logs:DescribeResourcePolicies,
logs:DescribeLogGroups,
logs:CreateLogGroup, logs:CreateLogStream, logs:PutRetentionPolicy
  (on aws/spans and /aws/application-signals/data)
```

If `agentcore_log_delivery` is used, additionally:

```
logs:CreateLogGroup, logs:DeleteLogGroup, logs:PutRetentionPolicy, logs:TagResource,
logs:PutDeliverySource, logs:GetDeliverySource, logs:DeleteDeliverySource,
logs:PutDeliveryDestination, logs:GetDeliveryDestination, logs:DeleteDeliveryDestination,
logs:CreateDelivery, logs:GetDelivery, logs:DeleteDelivery,
logs:AllowVendedLogDeliveryForResource (on the AgentCore resource ARNs)
```

## Validation

`post-api-helpers.sh` on `apply` prints, for example:

```
[ OK ] CloudWatch Logs resource policy: TransactionSearchAccess
[ OK ] Trace segment destination: CloudWatchLogs
[ OK ] Trace segment destination status: ACTIVE
[ OK ] Default indexing rule sampling percentage: 1.0
[ OK ] Trace segment destination: CloudWatchLogs (ACTIVE)
[ OK ] Default indexing rule: desired=1.0% actual=1.0%
[ OK ] Resource policy TransactionSearchAccess: grants xray.amazonaws.com
[WARN] Log group aws/spans does not exist yet; X-Ray creates it when the first span arrives
```

`PENDING` status right after apply is normal; AWS says it can take about
10 minutes to become `ACTIVE`. The `aws/spans` warning clears once any
service sends a span.

## Destroy behaviour

`terraform destroy` removes the Logs resource policy and the optional
AgentCore delivery resources. The provider's delete of
`aws_xray_trace_segment_destination` and `aws_xray_indexing_rule` is a no-op
by design, so `post-api-helpers.sh` calls
`aws xray update-trace-segment-destination --destination XRay` to actually
turn Transaction Search off, then validates the destination reads `XRay`.
Set `REVERT_TRANSACTION_SEARCH_ON_DESTROY=false` to skip that. The indexing
percentage is left as-is.

## What this does NOT do (per-agent steps)

These belong with the workload that deploys the agent, not with an
account-level customization:

- Adding the ADOT SDK (`aws-opentelemetry-distro>=0.18.0`) and running under
  `opentelemetry-instrument`.
- Setting `UNIFIED_TRACES_DESTINATION_ENABLED` on an AgentCore runtime to
  send spans to the agent's own log group instead of `aws/spans`.
- Enabling tracing on individual memory/gateway/tool resources.
- The OTEL environment variables for agents hosted outside AgentCore.

## References

- [Enable Transaction Search (CloudWatch)](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Enable-TransactionSearch.html)
- [Transaction Search with CloudFormation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Transaction-Search-Cloudformation.html)
- [Add observability to Bedrock AgentCore resources](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-configure.html)
- Terraform: [`aws_xray_trace_segment_destination`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/xray_trace_segment_destination),
  [`aws_xray_indexing_rule`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/xray_indexing_rule),
  [`aws_cloudwatch_log_resource_policy`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy),
  [`aws_cloudwatch_log_delivery`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery)
