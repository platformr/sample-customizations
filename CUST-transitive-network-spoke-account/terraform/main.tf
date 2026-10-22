# ------------------------------------------------------------------------------
# Transitive network SPOKE (deploy to any workload account)
#
#   discovery.tf   find the hub's Transit Gateway and IPAM pool through RAM
#   vpc.tf         VPC per region (CIDR from the hub pool), subnets, route tables
#   attachment.tf  Transit Gateway attachment + routes to the cloud CIDR
#   ssm.tf         SSM contract for workloads
#
# Requires CUST-transitive-network-hub-account in the networking account, with
# this account (or its OU / the organization) as a RAM principal.
# ------------------------------------------------------------------------------
