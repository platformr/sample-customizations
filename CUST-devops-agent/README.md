# CUST-devops-agent

> Turn on AWS DevOps Agent for the target account: create the IAM roles and an
> agent space with Terraform, then associate the account and enable the
> operator web app through the API in the post helper.

## What it does

- Creates two IAM roles trusted by `aidevops.amazonaws.com` (scoped to agent
  spaces in this account/region):
  - `DevOpsAgentRole-AgentSpace` with `AIDevOpsAgentAccessPolicy` plus an
    inline policy allowing creation of the Resource Explorer service-linked
    role (topology discovery).
  - `DevOpsAgentRole-WebappAdmin` with `AIDevOpsOperatorAppAccessPolicy`.
- Creates a DevOps Agent **agent space** (`aws_devopsagent_agent_space`).
- Publishes the agent space ID and role ARNs to SSM under
  `/platformr/CUST-devops-agent/` for the helpers.
- `post-api-helpers.sh` then:
  - associates this AWS account with the agent space as the `monitor`
    account (`AssociateService`, service id `aws`),
  - enables the operator app with the IAM auth flow (`EnableOperatorApp`),
  - validates and prints the operator app URL.

Only the **monitoring account** pattern is implemented: each target account
gets its own agent space and watches itself. That keeps the customization
self-contained (no cross-account role wiring, which would be a
cross-customization dependency).

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/iam.tf` | Agent space role + operator app role, trust policies, managed policy attachments |
| `terraform/main.tf` | `aws_devopsagent_agent_space`, SSM hand-off parameters |
| `api_helpers/pre-api-helpers.sh` | Checks the region is supported and that the CLI knows `aws devops-agent` |
| `api_helpers/post-api-helpers.sh` | `associate-service`, `enable-operator-app`, validation; on destroy confirms removal |

The Terraform AWS provider (>= 6.x) has a resource for the agent space but
not for service associations or the operator app, which is exactly the
situation the `api_helpers` layer exists for.

### Terraform → helper hand-off

The post helper never reads Terraform state. Terraform writes what the helper
needs to SSM:

```
/platformr/CUST-devops-agent/agent_space_id
/platformr/CUST-devops-agent/agent_space_arn
/platformr/CUST-devops-agent/agent_space_role_arn
/platformr/CUST-devops-agent/operator_app_role_arn
/platformr/CUST-devops-agent/agent_space_region
/platformr/CUST-devops-agent/agent_space_account_id
```

Reuse this pattern whenever a helper needs an ID that only Terraform knows.

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Must be one of us-east-1, us-west-2, eu-central-1, eu-west-1, ap-southeast-2, ap-northeast-1 (validated). |
| `agent_space_name` | `platformr-account-agent-space` | Agent space name. |
| `agent_space_description` | (text) | Agent space description. |
| `agent_space_locale` | `null` | e.g. `en`. |
| `kms_key_arn` | `null` | Optional CMK; key policy must allow `aidevops.amazonaws.com`. Changing it replaces the space. |
| `agent_space_role_name` | `DevOpsAgentRole-AgentSpace` | IAM role name. |
| `operator_app_role_name` | `DevOpsAgentRole-WebappAdmin` | IAM role name. |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `CUSTOMIZATION_NAME` | `CUST-devops-agent` | Must match `var.customization_name` (SSM path). |

## Permissions required by the deployment role

```
iam:CreateRole, iam:DeleteRole, iam:GetRole, iam:UpdateRole, iam:TagRole,
iam:AttachRolePolicy, iam:DetachRolePolicy, iam:ListAttachedRolePolicies,
iam:PutRolePolicy, iam:DeleteRolePolicy, iam:GetRolePolicy, iam:ListRolePolicies,
iam:PassRole (on the two roles above),
aidevops:CreateAgentSpace, aidevops:GetAgentSpace, aidevops:UpdateAgentSpace,
aidevops:DeleteAgentSpace, aidevops:ListAgentSpaces, aidevops:TagResource,
aidevops:ListTagsForResource,
aidevops:AssociateService, aidevops:ListAssociations, aidevops:ValidateAwsAssociations,
aidevops:EnableOperatorApp, aidevops:GetOperatorApp,
ssm:PutParameter, ssm:GetParameter, ssm:DeleteParameter, ssm:AddTagsToResource,
ssm:ListTagsForResource
```

The service-linked role for DevOps Agent is created automatically on first
use. Check the DevOps Agent IAM documentation for the current action list;
the `aidevops:` prefix is the service's IAM namespace.

## Build image requirement

`aws devops-agent` is a recent addition to AWS CLI v2. The pre helper probes
for it; if it is missing, Terraform still creates roles and the agent space,
and the post helper logs a warning and skips association/operator-app
enablement instead of failing. Re-run `apply` after updating the CLI.

## Validation

`post-api-helpers.sh` on `apply` prints, for example:

```
[ OK ] SSM /platformr/CUST-devops-agent/agent_space_id: 08975e27-...
[INFO] Associating account 123456789012 with agent space 08975e27-... as 'monitor'...
[ OK ] associate-service (aws, monitor)
[INFO] Enabling operator app (IAM auth flow)...
[ OK ] enable-operator-app (iam)
[ OK ] Agent space 08975e27-...: platformr-account-agent-space
[ OK ] AWS account association status: ACTIVE
[ OK ] Operator app URL: https://....
```

Re-running `apply` detects the existing association and operator app and
skips both calls.

## Destroy behaviour

`terraform destroy` deletes the agent space (which removes its associations,
operator app and all investigation data; this cannot be undone), the SSM
parameters and the IAM roles. The post helper confirms the SSM parameters
and the agent space are gone.

## References

- [AWS DevOps Agent CLI onboarding guide](https://docs.aws.amazon.com/devopsagent/latest/userguide/getting-started-with-aws-devops-agent-cli-onboarding-guide.html)
- [DevOps Agent API reference](https://docs.aws.amazon.com/devopsagent/latest/APIReference/API_Operations.html)
- Terraform: [`aws_devopsagent_agent_space`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/devopsagent_agent_space)
