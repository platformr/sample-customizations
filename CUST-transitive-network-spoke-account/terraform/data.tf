data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Standard AZs only (no Local Zones) in each spoke region.
data "aws_availability_zones" "available" {
  for_each = toset(var.spoke_regions)

  region = each.key

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
