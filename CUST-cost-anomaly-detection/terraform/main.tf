# ------------------------------------------------------------------------------
# AWS Cost Anomaly Detection
#
#   * One DIMENSIONAL monitor on the SERVICE dimension ("AWS services" monitor):
#     evaluates every AWS service in the account for anomalous spend.
#   * One subscription that emails var.alert_email when an anomaly's total
#     impact is >= var.alert_threshold_usd.
#
# Cost Anomaly Detection has no per-region state; the provider talks to the
# us-east-1 Cost Explorer endpoint.
# ------------------------------------------------------------------------------

resource "aws_ce_anomaly_monitor" "services" {
  name              = var.monitor_name
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "email" {
  name      = var.subscription_name
  frequency = var.alert_frequency

  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.alert_threshold_usd)]
    }
  }
}

# Hand-off for post-api-helpers.sh (names only; nothing sensitive).
resource "aws_ssm_parameter" "handoff" {
  for_each = {
    monitor_name      = var.monitor_name
    subscription_name = var.subscription_name
    alert_email       = var.alert_email
  }

  name        = "/platformr/${var.customization_name}/${each.key}"
  description = "Published by ${var.customization_name} for api_helpers."
  type        = "String"
  value       = each.value
}
