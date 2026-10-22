# CUST-cost-anomaly-detection

> Enable AWS Cost Anomaly Detection for the account with an "AWS services"
> monitor and a daily email alert. Engineers set the recipient by editing
> `var.alert_email`.

## What it does

- Creates one **DIMENSIONAL / SERVICE** anomaly monitor. This is the
  "AWS services" monitor type that evaluates every service's spend in the
  account; AWS allows one per account.
- Creates one alert **subscription** that emails `var.alert_email` on a
  `DAILY` (or `WEEKLY`) summary whenever an anomaly's total impact is at
  least `var.alert_threshold_usd` (default 100 USD).
- Publishes the names to SSM under `/platformr/CUST-cost-anomaly-detection/`
  so the post helper can validate without reading state.

Cost Anomaly Detection is account-global and served from `us-east-1`;
`var.region` stays at its default.

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/main.tf` | `aws_ce_anomaly_monitor`, `aws_ce_anomaly_subscription`, SSM hand-off |
| `api_helpers/pre-api-helpers.sh` | Warns if another SERVICE monitor already exists (apply would fail) |
| `api_helpers/post-api-helpers.sh` | Verifies monitor + subscription exist and the subscriber email matches |

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `alert_email` | `cost-alerts@example.com` | **Change this.** Validated as an email address; the post helper warns if it is still `example.com`. |
| `alert_frequency` | `DAILY` | `DAILY` or `WEEKLY` (email cannot use `IMMEDIATE`). |
| `alert_threshold_usd` | `100` | Minimum total impact in USD to alert on. |
| `monitor_name` | `platformr-aws-services-monitor` | |
| `subscription_name` | `platformr-cost-anomaly-alerts` | |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `CUSTOMIZATION_NAME` | `CUST-cost-anomaly-detection` | SSM path prefix. |

To send to multiple addresses or to Slack/Chatbot, add more `subscriber`
blocks or switch to an SNS subscriber with `frequency = "IMMEDIATE"` (see the
provider docs for the SNS topic policy).

## Permissions required by the deployment role

```
ce:CreateAnomalyMonitor, ce:GetAnomalyMonitors, ce:UpdateAnomalyMonitor, ce:DeleteAnomalyMonitor,
ce:CreateAnomalySubscription, ce:GetAnomalySubscriptions, ce:UpdateAnomalySubscription,
ce:DeleteAnomalySubscription, ce:TagResource, ce:UntagResource, ce:ListTagsForResource,
ssm:PutParameter, ssm:GetParameter, ssm:DeleteParameter, ssm:AddTagsToResource, ssm:ListTagsForResource
```

The account must have Cost Explorer enabled (it is enabled automatically the
first time the console is opened, or on first API call; new accounts may need
up to 24 hours before data appears).

## Validation

```
[ OK ] Anomaly monitor 'platformr-aws-services-monitor': arn:aws:ce::123456789012:anomalymonitor/...
[ OK ] Anomaly subscription 'platformr-cost-anomaly-alerts': arn:aws:ce::123456789012:anomalysubscription/...
[ OK ] Subscriber email: finops@yourcompany.com
[ OK ] Alert frequency: DAILY
```

## Destroy behaviour

`terraform destroy` deletes the subscription, the monitor and the SSM
parameters. The post helper confirms the monitor is gone. Historical
anomalies are no longer visible once the monitor is deleted.

## References

- [AWS Cost Anomaly Detection](https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html)
- Terraform: [`aws_ce_anomaly_monitor`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_monitor),
  [`aws_ce_anomaly_subscription`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_subscription)
