# Platformr Customizations — sample repository

Example repository for **Platformr Customizations**: a way to deploy
account-level configuration to AWS accounts with Terraform plus optional
shell/python helpers, without the operational overhead of AFT-style
pipelines.

Each top-level directory prefixed `CUST-` is one customization. Platformr
clones this repository, picks one customization, and runs it against one
target account with one action (`apply`, `diff` or `destroy`).

## Customizations in this repository

| Directory | What it does | Terraform | Helpers |
| --- | --- | --- | --- |
| [`CUST-transaction-search`](CUST-transaction-search/) | Enables CloudWatch Transaction Search: the prerequisite for X-Ray Transaction Search, Application Signals and Bedrock AgentCore (GenAI) observability. Optional AgentCore vended log/trace delivery. | Logs resource policy, X-Ray trace destination, indexing rule, log delivery | Validation in bash + python; reverts destination on destroy |
| [`CUST-devops-agent`](CUST-devops-agent/) | Turns on AWS DevOps Agent: IAM roles, agent space, account association, operator app. | IAM roles, agent space, SSM hand-off | Associates account + enables operator app (no Terraform resource exists); validation |
| [`CUST-iam-password-policy`](CUST-iam-password-policy/) | Sets the IAM account password policy to CIS values (Config rule `iam-password-policy` defaults). Global. | `aws_iam_account_password_policy` | Reads the policy back and checks every field |
| [`CUST-cost-anomaly-detection`](CUST-cost-anomaly-detection/) | Cost Anomaly Detection with an AWS-services monitor and a daily email alert (`var.alert_email`). | `aws_ce_anomaly_monitor`, `aws_ce_anomaly_subscription` | Warns on a conflicting monitor; validates monitor + subscriber |
| [`CUST-bedrock-model-enablement`](CUST-bedrock-model-enablement/) | Enables Anthropic Claude Fable 5.1 and Opus 5.5 on Bedrock: use-case form + model agreements (us-east-1). | `aws_bedrock_use_case_for_model_access`, `aws_bedrock_foundation_model_agreement` | Sets data retention mode (no TF resource); validates model availability |
| [`CUST-ec2-ebs-encryption-by-default`](CUST-ec2-ebs-encryption-by-default/) | EBS encryption by default for the region, optional CMK as default key. | `aws_ebs_encryption_by_default`, `aws_ebs_default_kms_key` | Validates the setting and default key |
| [`CUST-enforce-imdsv2-on-account`](CUST-enforce-imdsv2-on-account/) | IMDSv2 required by default for new instances, plus account-level enforcement. | `aws_ec2_instance_metadata_defaults` | Sets `HttpTokensEnforced` (no TF resource); validates |
| [`CUST-eks-cluster`](CUST-eks-cluster/) | Starter EKS cluster: own VPC, Auto Mode compute, Helm-installed StorageClass/IngressClass/metrics-server, SSM parameter contract for workloads. | VPC + EKS modules, `helm_release`, `aws_ssm_parameter` | Pre-destroy orphan check; validates cluster, SSM contract, in-cluster defaults |
| [`CUST-delete-default-vpcs`](CUST-delete-default-vpcs/) | Deletes the default VPC in every enabled region; the helper-driven example. | SSM marker only | Pre helper deletes; post helper verifies and records the result in SSM |
| [`CUST-transitive-network-hub-account`](CUST-transitive-network-hub-account/) | **Networking account only.** Transit Gateway in one or two regions (peered), hierarchical IPAM shared to the organization, SSM contract. | TGW + peering + routes, IPAM pools, RAM shares (per-resource `region`) | Prerequisite checks; destroy-blocker report; validates TGWs, peering, pools, shares |
| [`CUST-transitive-network-spoke-account`](CUST-transitive-network-spoke-account/) | Any workload account: a VPC per region (one or two) allocated from the hub's shared IPAM pool and attached to the hub's Transit Gateway. **Requires the hub customization** (the one sanctioned cross-customization dependency). | VPC, subnets, TGW attachment, routes, SSM contract | Checks the RAM shares are visible; validates VPC, attachment, routes |
| [`_TEMPLATE`](_TEMPLATE/) | Starting point for new customizations. Not deployable as-is. | Skeleton | Skeleton |

## How a customization runs

**apply** and **destroy**:

```
1. clone repo
2. cd CUST-<suffix>/api_helpers && ./pre-api-helpers.sh
3. cd ../terraform && terraform init && terraform <apply | destroy>
4. cd ../api_helpers && ./post-api-helpers.sh
```

**diff** (Terraform only):

```
1. clone repo
2. cd CUST-<suffix>/terraform && terraform init && terraform plan
```

The build environment provides credentials for the target account, injects
the Terraform backend, and exports `PLATFORMR_ACTION` (`apply` or `destroy`)
so the helper scripts know what is happening. A customization may be running
in many accounts at once; customizations never depend on each other and
there is no ordering between them.

### What runs on a diff

A `diff` is a preview of the infrastructure-as-code change only. Platformr
runs `terraform plan` inside `terraform/` and **does not execute
`pre-api-helpers.sh` or `post-api-helpers.sh`**. Consequences for authors:

- Helper scripts only ever see `PLATFORMR_ACTION=apply` or `destroy`. They do
  not need, and should not have, a `diff` branch.
- Anything a reviewer must see at plan time has to be expressed in
  Terraform. Checks or configuration that live in helpers are invisible to a
  diff.
- Helpers still need to be idempotent, because the same customization is
  applied to the same account repeatedly, not because of diff.

## Anatomy of a customization

```
CUST-<suffix>/
├── README.md                     what / how / inputs / permissions / validation / destroy
├── api_helpers/
│   ├── pre-api-helpers.sh        before terraform: context, pre-checks, opt-ins
│   ├── post-api-helpers.sh       after terraform: API-only config + validation
│   └── python/
│       ├── requirements.txt      deps for python helpers (installed into a venv)
│       └── *.py                  optional boto3 helpers, run via run_python
└── terraform/
    ├── versions.tf               terraform + provider constraints (no backend!)
    ├── providers.tf              aws provider with default_tags
    ├── variables.tf              region, customization_name, feature inputs
    ├── data.tf                   caller identity / partition / region
    ├── main.tf                   resources
    └── outputs.tf
```

Shared code lives in [`lib/`](lib/) (today: `lib/bash/common.sh` with
logging, action detection, AWS context and validation helpers). A
customization may use `lib/`; it may not reference another `CUST-*`.

## Creating a new customization

```bash
scripts/new-customization.sh my-feature "Enable My Feature in the account"
```

Then edit `CUST-my-feature/terraform/main.tf`, the two helper scripts and
the README, and validate:

```bash
scripts/validate-customization.sh CUST-my-feature
```

The validator runs `terraform fmt -check`, `terraform init -backend=false`,
`terraform validate`, `bash -n`/shellcheck, `py_compile`, layout checks and
anti-pattern greps (backend blocks, remote state, cross-customization
references, hard-coded account IDs).

### With an AI coding agent (Claude Code, Codex, Kiro, Cursor, Copilot, Gemini CLI)

This repo ships three [Agent Skills](https://agentskills.io) in
[`skills/`](skills/) so any coding agent follows the same process:

| Skill | Purpose |
| --- | --- |
| [`create-customization`](skills/create-customization/SKILL.md) | Scaffold + implement a new `CUST-*` end to end |
| [`write-api-helpers`](skills/write-api-helpers/SKILL.md) | Rules and patterns for pre/post helper scripts and python helpers |
| [`validate-customization`](skills/validate-customization/SKILL.md) | Run the validator and fix what it reports |

`skills/` is the single source of truth. The folders each agent scans are
symlinks to it, committed for Claude Code (`.claude/skills`), the shared
`.agents/skills` convention (Codex, Gemini CLI, Cursor, Copilot) and Kiro
(`.kiro/skills`). For other agents, or to use copies instead of symlinks:

```bash
scripts/link-skills.sh all
```

Always-on rules live in [`AGENTS.md`](AGENTS.md), which most agents read
automatically (`CLAUDE.md` includes it). Agents without native skill
support are told there to open the `SKILL.md` files directly.

Ask, for example: *"Create a customization that enables GuardDuty with
malware protection"*. The agent will scaffold from `_TEMPLATE`, research
the Terraform resources, write helpers with validation functions, document
the IAM permissions, and run the validator.

See [`skills/README.md`](skills/README.md) for the skill format, how to add
one, and how to adapt them when you repurpose this repo.

## Design rules (summary)

1. One directory per customization, named `CUST-<suffix>`.
2. Self-contained: no dependencies on other customizations, no backend block,
   no hard-coded account IDs.
3. Idempotent: safe to apply repeatedly; helpers check before they change.
4. Helpers handle `apply` and `destroy` only; a `diff` runs just `terraform plan`.
5. Prefer Terraform; use helpers only for what Terraform cannot do, and for
   validation.
6. Post helpers validate and **echo** status (`[ OK ]` / `[FAIL]`) but do not
   fail the build.
7. Hand values from Terraform to helpers through SSM parameters under
   `/platformr/<CUST-name>/`, never through state.
8. Say what `destroy` does; revert in the post helper when Terraform cannot.

See [`AGENTS.md`](AGENTS.md) for the full list.

## Local prerequisites

- Terraform >= 1.5 (the examples were validated with 1.5.7 and AWS provider 6.69)
- AWS CLI v2 (recent; `aws devops-agent` needs a 2026 build)
- python3 (for python helpers)
- Optional: `shellcheck`, `tflint`

## Comparison with AFT

Like AWS Control Tower Account Factory for Terraform (AFT), each
customization is a Terraform root module with pre/post hooks. Unlike AFT
there is no pipeline-per-account, no global/account customization split and
no ordering: every run is exactly one customization against one account,
which keeps failures isolated and makes each directory independently
testable.
