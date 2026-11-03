# permission-boundary

An IAM managed policy used as the **permissions boundary** on every role Terraform creates
(pipeline roles, ECS task roles, RDS, Backup, Firehose, Lambda, MWAA roles…).

**Status:** implemented in Step 3.

## How a boundary works

A role can only do what **both** its own policies **and** the boundary allow. The boundary
grants nothing by itself. So even a role with `AdministratorAccess`, such as `gha-apply`,
cannot do anything the boundary denies.

## What it denies

| Statement | Blocks |
|---|---|
| `DenyIamUsersAndKeys` | Creating IAM users, access keys or console passwords |
| `DenyChangingThisBoundary` | Editing or deleting the boundary policy itself |
| `DenyRemovingBoundaryFromRoles` | Taking the boundary off a role |
| `DenyRolesWithoutThisBoundary` | Creating a role (or changing a role's boundary) unless this boundary is attached, so no role can escape it |
| `DenyDisablingSecurityServices` | Stopping or deleting CloudTrail, GuardDuty, Security Hub, Config, Access Analyzer, Inspector, Macie |
| `DenyUnapprovedRegions` | Any regional API call outside `allowed_regions` (global services such as IAM, CloudFront and Route 53 are exempt) |

## Changing the boundary later

Because of `DenyChangingThisBoundary`, the pipeline role cannot update the boundary. A change
is applied by a DevOps engineer with the `DevOps` SSO permission set (which is not bounded):

```powershell
$env:AWS_PROFILE = "mmm-dev-devops"
terraform apply -target=module.permission_boundary
```

This is deliberate: the boundary is the last guard rail, so changing it needs a human.

## Inputs

| Name | Type | Description |
|---|---|---|
| `name_prefix` | string | e.g. `mmm-dev` → policy `mmm-dev-permission-boundary` |
| `allowed_regions` | list(string) | Approved regions, plus `us-east-1` and the DR region |
| `tags` | map(string) | Extra tags |

## Outputs

| Name | Description |
|---|---|
| `policy_arn` | Pass as `permissions_boundary` on every role |
| `policy_name` | Policy name |
