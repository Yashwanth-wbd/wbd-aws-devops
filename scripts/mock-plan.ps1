<#
.SYNOPSIS
  Plans environment stacks offline with mocked AWS providers (no account or credentials needed).

.DESCRIPTION
  Runs `terraform test` with infra/environments/<env>/tests/mock-plan.tftest.hcl, which has two
  plan-only runs: the environment's terraform.tfvars as is, and every optional feature switched on
  (cross-region copy, vault lock, Splunk, Transit Gateway, Resolver, Application Signals, DB
  bootstrap). AWS data sources return fixed fake values; resource attributes stay "known after
  apply", like in a first real plan.

  It catches what `validate` cannot: count/for_each that depend on values only known after apply,
  failing preconditions and variable validations, wrong map keys, and tfvars type errors.
  It does NOT check permissions, quotas or names that already exist - that needs the real plan.

  The repo is copied to %TEMP% first (Terraform is slow and fragile on the UNC share).
  terraform.yml runs the same tests in CI.

.EXAMPLE
  .\scripts\mock-plan.ps1 -Environment dev,staging,prod
.EXAMPLE
  .\scripts\mock-plan.ps1 -Environment prod -ShowPlan    # prints the plans (resource list and "Plan: N to add")
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [ValidateSet('dev', 'staging', 'prod')] [string[]]$Environment,
  [switch]$ShowPlan
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$work = Join-Path $env:TEMP 'mmm-mockplan'
if (-not $env:TF_PLUGIN_CACHE_DIR) {
  $env:TF_PLUGIN_CACHE_DIR = Join-Path $env:USERPROFILE '.terraform.d\plugin-cache'
}
New-Item -ItemType Directory -Force $env:TF_PLUGIN_CACHE_DIR | Out-Null

if (Test-Path $work) { Remove-Item -Recurse -Force $work }
robocopy (Join-Path $root 'infra') (Join-Path $work 'infra') /S /XD .terraform /NFL /NDL /NJH /NJS /NP | Out-Null
robocopy (Join-Path $root 'scripts') (Join-Path $work 'scripts') /NFL /NDL /NJH /NJS /NP | Out-Null

$failed = @()
foreach ($e in $Environment) {
  Write-Host "== $e" -ForegroundColor Cyan
  Push-Location (Join-Path $work "infra\environments\$e")
  try {
    terraform init -backend=false -no-color | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed for $e" }
    $out = terraform test -no-color -verbose 2>&1
    $code = $LASTEXITCODE
    if ($ShowPlan -or $code -ne 0) { $out | ForEach-Object { "$_" } }
    $out | Select-String '^Plan: |run "|Success!|Failure!' | ForEach-Object { "  $($_.Line.Trim())" }
    if ($code -ne 0) { $failed += $e }
  } finally {
    Pop-Location
  }
}

if ($failed.Count -gt 0) { Write-Host "Mock plan FAILED: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "Mock plan passed: $($Environment -join ', ')" -ForegroundColor Green
