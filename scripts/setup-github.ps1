<#
.SYNOPSIS
  Creates a GitHub Environment with its protection rules and sets its variables from Terraform outputs.

.DESCRIPTION
  Protection per environment:
    dev      no reviewers; deployments from main only
    staging  required reviewers (EY delivery lead); main (Terraform) and v* tags (releases)
    prod     required reviewers (WBD approvers), prevent self-review; main (Terraform) and v* tags

  With -ModelApproverTeams/-ModelApproverUsers it also creates <env>-model-promotion (Step 13):
  required reviewers (WBD model approvers), prevent self-review, main only. model-governance.yml
  approves a model package (gha-model-approve role) only from a job in that environment.

  -DatabricksClientId sets DATABRICKS_CLIENT_ID (the Databricks deploy service principal that
  databricks.yml federates to with GitHub OIDC) on the Environment.

  Variables come from `terraform output -json github_environment_variables` (Environment level) and
  `github_repository_variables` (repository level, used by PR plans and the drift check), so the
  Terraform state must be readable (SSO DevOps profile). Nothing secret is set.

  Needs: gh (logged in as a repo admin), terraform, AWS credentials for that account.

.EXAMPLE
  .\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment dev
.EXAMPLE
  .\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment staging -ReviewerTeams ey-delivery-leads `
    -SourceEcrReadRoleArn arn:aws:iam::111111111111:role/mmm-dev-gha-ecr-read -SourceEcrRegistry 111111111111.dkr.ecr.us-east-1.amazonaws.com
.EXAMPLE
  .\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment prod -ReviewerTeams wbd-release-approvers `
    -ModelApproverTeams wbd-model-approvers -SkipVariables
#>
[CmdletBinding()]
param(
  # add actual value
  [string]$Repo = 'Yashwanth-wbd/wbd-aws-devops',
  [Parameter(Mandatory)] [ValidateSet('dev', 'staging', 'prod')] [string]$Environment,
  [string]$TerraformDir,
  [string[]]$ReviewerTeams = @(),
  [string[]]$ReviewerUsers = @(),
  [string]$SourceEcrReadRoleArn,
  [string]$SourceEcrRegistry,
  [string[]]$ModelApproverTeams = @(),
  [string[]]$ModelApproverUsers = @(),
  [string]$DatabricksClientId,
  [switch]$SkipVariables
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
if (-not $TerraformDir) { $TerraformDir = Join-Path $root "infra\environments\$Environment" }
$org = $Repo.Split('/')[0]

function Invoke-Gh {
  param([string[]]$GhArgs, [string]$Body)
  if ($Body) {
    $tmp = New-TemporaryFile
    [IO.File]::WriteAllText($tmp, $Body)
    $out = & gh @GhArgs --input $tmp.FullName 2>&1
    Remove-Item $tmp
  } else {
    $out = & gh @GhArgs 2>&1
  }
  if ($LASTEXITCODE -ne 0) { throw "gh $($GhArgs -join ' ') failed: $out" }
  $out
}

function Get-Reviewers {
  param([string[]]$Teams, [string[]]$Users)
  $list = @()
  foreach ($t in $Teams) { $list += @{ type = 'Team'; id = [int](Invoke-Gh @('api', "orgs/$org/teams/$t", '--jq', '.id')) } }
  foreach ($u in $Users) { $list += @{ type = 'User'; id = [int](Invoke-Gh @('api', "users/$u", '--jq', '.id')) } }
  , $list
}

function Add-RefPolicies {
  param([string]$EnvName, [hashtable[]]$Policies)
  $existing = Invoke-Gh @('api', "repos/$Repo/environments/$EnvName/deployment-branch-policies", '--jq', '.branch_policies[].name')
  foreach ($p in $Policies) {
    if ($existing -contains $p.name) { continue }
    Invoke-Gh @('api', '-X', 'POST', "repos/$Repo/environments/$EnvName/deployment-branch-policies") ($p | ConvertTo-Json) | Out-Null
    Write-Host "  allowed ref: $($p.type) $($p.name)"
  }
}

# ------------------------------------------------------------------ environment + protection
$reviewers = Get-Reviewers $ReviewerTeams $ReviewerUsers
if ($Environment -ne 'dev' -and $reviewers.Count -eq 0) {
  Write-Warning "$Environment has no reviewers yet. Re-run with -ReviewerTeams/-ReviewerUsers once WBD names them."
}

$envBody = @{
  wait_timer               = 0
  prevent_self_review      = ($Environment -eq 'prod')
  reviewers                = $reviewers
  deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true }
} | ConvertTo-Json -Depth 5
Invoke-Gh @('api', '-X', 'PUT', "repos/$Repo/environments/$Environment") $envBody | Out-Null
Write-Host "Environment ${Environment}: reviewers=$($reviewers.Count), prevent_self_review=$($Environment -eq 'prod')"

$policies = @(@{ name = 'main'; type = 'branch' })
if ($Environment -ne 'dev') { $policies += @{ name = 'v*'; type = 'tag' } }
Add-RefPolicies $Environment $policies

# ------------------------------------------------------------------ Step 13: model promotion approval
$modelApprovers = Get-Reviewers $ModelApproverTeams $ModelApproverUsers
if ($modelApprovers.Count -gt 0) {
  $modelEnv = "$Environment-model-promotion"
  $modelBody = @{
    wait_timer               = 0
    prevent_self_review      = $true
    reviewers                = $modelApprovers
    deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true }
  } | ConvertTo-Json -Depth 5
  Invoke-Gh @('api', '-X', 'PUT', "repos/$Repo/environments/$modelEnv") $modelBody | Out-Null
  Write-Host "Environment ${modelEnv}: reviewers=$($modelApprovers.Count), prevent_self_review=True"
  Add-RefPolicies $modelEnv @(@{ name = 'main'; type = 'branch' })
} else {
  Write-Host "No -ModelApproverTeams/-ModelApproverUsers: $Environment-model-promotion not created (model promotion stays blocked)."
}

if ($SkipVariables) { return }

# ------------------------------------------------------------------ variables from Terraform outputs
Push-Location $TerraformDir
try {
  $envVars = terraform output -json github_environment_variables | ConvertFrom-Json
  $repoVars = terraform output -json github_repository_variables | ConvertFrom-Json
} finally {
  Pop-Location
}
if (-not $envVars) { throw "No github_environment_variables output in $TerraformDir - apply the stack first." }

foreach ($p in $envVars.PSObject.Properties) {
  Invoke-Gh @('variable', 'set', $p.Name, '--repo', $Repo, '--env', $Environment, '--body', [string]$p.Value) | Out-Null
  Write-Host "  env  $($p.Name) = $($p.Value)"
}
foreach ($p in $repoVars.PSObject.Properties) {
  Invoke-Gh @('variable', 'set', $p.Name, '--repo', $Repo, '--body', [string]$p.Value) | Out-Null
  Write-Host "  repo $($p.Name) = $($p.Value)"
}
if ($DatabricksClientId) {
  Invoke-Gh @('variable', 'set', 'DATABRICKS_CLIENT_ID', '--repo', $Repo, '--env', $Environment, '--body', $DatabricksClientId) | Out-Null
  Write-Host "  env  DATABRICKS_CLIENT_ID = $DatabricksClientId"
}

# Promotion source (previous environment's registry) - staging and prod only
if ($Environment -ne 'dev') {
  if ($SourceEcrReadRoleArn -and $SourceEcrRegistry) {
    Invoke-Gh @('variable', 'set', 'SOURCE_ECR_READ_ROLE_ARN', '--repo', $Repo, '--env', $Environment, '--body', $SourceEcrReadRoleArn) | Out-Null
    Invoke-Gh @('variable', 'set', 'SOURCE_ECR_REGISTRY', '--repo', $Repo, '--env', $Environment, '--body', $SourceEcrRegistry) | Out-Null
    Write-Host "  env  SOURCE_ECR_READ_ROLE_ARN / SOURCE_ECR_REGISTRY set"
  } else {
    Write-Warning "Pass -SourceEcrReadRoleArn and -SourceEcrRegistry (the previous environment) for image promotion."
  }
}
Write-Host "Done: $Repo / $Environment" -ForegroundColor Green
