data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Any member account may describe its organization; the ARN is the RAM
# principal when sharing with the whole organization.
data "aws_organizations_organization" "current" {}
