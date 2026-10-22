# CUST-iam-password-policy

> Set the IAM account password policy to CIS-aligned values (the defaults of
> the AWS Config managed rule `IAM_PASSWORD_POLICY`).

## What it does

Sets the account-wide IAM password policy to:

| Setting | Value | Config rule parameter |
| --- | --- | --- |
| Minimum length | 14 | `MinimumPasswordLength` |
| Reuse prevention | 24 previous passwords | `PasswordReusePrevention` |
| Max age | 90 days | `MaxPasswordAge` |
| Uppercase / lowercase / numbers / symbols | all required | `Require*` |
| Users may change own password | yes | (not evaluated by the rule) |
| Hard expiry | no | (not evaluated by the rule) |

With these values an account evaluates **COMPLIANT** for the `iam-password-policy`
Config rule at its default parameters. The policy is global: it applies to
every region of the account, so this customization only needs to run once per
account.

## How it is implemented

| Layer | Responsibility |
| --- | --- |
| `terraform/main.tf` | `aws_iam_account_password_policy` |
| `api_helpers/pre-api-helpers.sh` | Prints the policy currently in force (context only) |
| `api_helpers/post-api-helpers.sh` | Reads the policy back with `iam get-account-password-policy` and checks every field |

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `minimum_password_length` | `14` | Validated to be >= 14. |
| `password_reuse_prevention` | `24` | 1–24. |
| `max_password_age` | `90` | 1–1095 days. |
| `require_uppercase_characters` | `true` | |
| `require_lowercase_characters` | `true` | |
| `require_numbers` | `true` | |
| `require_symbols` | `true` | |
| `allow_users_to_change_password` | `true` | |
| `hard_expiry` | `false` | |

Environment variables consumed by the helpers:

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORMR_ACTION` | `apply` | `apply` or `destroy`; set by the build. Helpers are not run on `diff`. |
| `EXPECT_MIN_LENGTH` | `14` | Only change if `minimum_password_length` was changed. |
| `EXPECT_REUSE_PREVENTION` | `24` | Only change if `password_reuse_prevention` was changed. |
| `EXPECT_MAX_AGE` | `90` | Only change if `max_password_age` was changed. |

## Permissions required by the deployment role

```
iam:GetAccountPasswordPolicy
iam:UpdateAccountPasswordPolicy
iam:DeleteAccountPasswordPolicy
```

## Validation

```
[ OK ] MinimumPasswordLength: 14
[ OK ] PasswordReusePrevention: 24
[ OK ] MaxPasswordAge: 90
[ OK ] RequireUppercaseCharacters: True
[ OK ] RequireLowercaseCharacters: True
[ OK ] RequireNumbers: True
[ OK ] RequireSymbols: True
[ OK ] AllowUsersToChangePassword: True
[ OK ] ExpirePasswords: True
```

## Destroy behaviour

`terraform destroy` deletes the custom policy. The account reverts to the AWS
default password policy, which the Config rule reports as NON_COMPLIANT. The
post helper confirms the custom policy is gone.

## References

- [AWS Config rule: iam-password-policy](https://docs.aws.amazon.com/config/latest/developerguide/iam-password-policy.html)
- [Setting an account password policy for IAM users](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_passwords_account-policy.html)
- Terraform: [`aws_iam_account_password_policy`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_account_password_policy)
