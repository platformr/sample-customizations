# ------------------------------------------------------------------------------
# OPTIONAL: Bedrock AgentCore vended log + trace delivery
#
# AgentCore runtime agents get a log group automatically. Memory and gateway
# resources do NOT; the AWS docs configure them with PutDeliverySource /
# PutDeliveryDestination / CreateDelivery. Terraform has resources for all
# three, so when `agentcore_log_delivery` is non-empty we wire them up here.
#
# Trace delivery (log_type = TRACES -> XRAY destination) requires Transaction
# Search to be active, which is why this lives in the same customization.
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "agentcore" {
  for_each = var.agentcore_log_delivery

  name              = "/aws/vendedlogs/bedrock-agentcore/${each.key}"
  retention_in_days = var.agentcore_log_retention_days
}

resource "aws_cloudwatch_log_delivery_source" "agentcore_logs" {
  for_each = var.agentcore_log_delivery

  name         = "${each.key}-logs-source"
  log_type     = "APPLICATION_LOGS"
  resource_arn = each.value
}

resource "aws_cloudwatch_log_delivery_source" "agentcore_traces" {
  for_each = var.agentcore_log_delivery

  name         = "${each.key}-traces-source"
  log_type     = "TRACES"
  resource_arn = each.value
}

resource "aws_cloudwatch_log_delivery_destination" "agentcore_logs" {
  for_each = var.agentcore_log_delivery

  name = "${each.key}-logs-destination"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.agentcore[each.key].arn
  }
}

resource "aws_cloudwatch_log_delivery_destination" "agentcore_traces" {
  for_each = var.agentcore_log_delivery

  name                      = "${each.key}-traces-destination"
  delivery_destination_type = "XRAY"

  depends_on = [aws_xray_trace_segment_destination.this]
}

resource "aws_cloudwatch_log_delivery" "agentcore_logs" {
  for_each = var.agentcore_log_delivery

  delivery_source_name     = aws_cloudwatch_log_delivery_source.agentcore_logs[each.key].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.agentcore_logs[each.key].arn
}

resource "aws_cloudwatch_log_delivery" "agentcore_traces" {
  for_each = var.agentcore_log_delivery

  delivery_source_name     = aws_cloudwatch_log_delivery_source.agentcore_traces[each.key].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.agentcore_traces[each.key].arn
}
