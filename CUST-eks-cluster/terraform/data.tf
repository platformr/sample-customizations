data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Exclude Local Zones / Wavelength (opt-in) so subnets land in standard AZs.
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
