<#
.SYNOPSIS
  Keeps staging and prod on the same Terraform code as dev.

.DESCRIPTION
  dev is the source. The shared stack files (everything except backend.tf, terraform.tfvars and
  README.md) are copied to infra/environments/staging and prod. Environment differences live only
  in terraform.tfvars and in conditions on var.environment inside the shared files.

  -Check only compares and exits 1 if a file differs (repo-checks.yml runs the same check in CI).

.EXAMPLE
  .\scripts\sync-environments.ps1            # after changing a .tf file in dev
.EXAMPLE
  .\scripts\sync-environments.ps1 -Check
#>
[CmdletBinding()]
param(
  [string[]]$Targets = @('staging', 'prod'),
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
$envRoot = Join-Path (Split-Path $PSScriptRoot) 'infra\environments'
$source = Join-Path $envRoot 'dev'
$perEnv = @('backend.tf', 'terraform.tfvars', 'README.md')

$shared = Get-ChildItem $source -File | Where-Object {
  ($_.Extension -eq '.tf' -or $_.Name -eq '.terraform.lock.hcl') -and $perEnv -notcontains $_.Name
}

$diffs = 0
foreach ($t in $Targets) {
  $dir = Join-Path $envRoot $t
  if (-not (Test-Path $dir)) { throw "$dir does not exist" }

  foreach ($f in $shared) {
    $dst = Join-Path $dir $f.Name
    $same = (Test-Path $dst) -and ((Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dst).Hash)
    if ($same) { continue }
    if ($Check) { Write-Host "DIFFERS  $t\$($f.Name)" -ForegroundColor Red; $diffs++ }
    else { Copy-Item $f.FullName $dst -Force; Write-Host "copied   $t\$($f.Name)" }
  }

  # Terraform tests (offline mock plan)
  New-Item -ItemType Directory -Force (Join-Path $dir 'tests') | Out-Null
  foreach ($f in Get-ChildItem (Join-Path $source 'tests') -Filter *.tftest.hcl) {
    $dst = Join-Path $dir "tests\$($f.Name)"
    if ((Test-Path $dst) -and ((Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dst).Hash)) { continue }
    if ($Check) { Write-Host "DIFFERS  $t\tests\$($f.Name)" -ForegroundColor Red; $diffs++ }
    else { Copy-Item $f.FullName $dst -Force; Write-Host "copied   $t\tests\$($f.Name)" }
  }

  # ECS templates: same content, family renamed (mmm-dev-api -> mmm-stg-api)
  $short = @{ staging = 'stg'; prod = 'prd' }[$t]
  $ecsSrc = Join-Path (Split-Path $PSScriptRoot) 'ecs\dev'
  $ecsDst = Join-Path (Split-Path $PSScriptRoot) "ecs\$t"
  New-Item -ItemType Directory -Force $ecsDst | Out-Null
  foreach ($j in Get-ChildItem $ecsSrc -Filter *.json) {
    $want = [IO.File]::ReadAllText($j.FullName).Replace('"mmm-dev-', "`"mmm-$short-").Replace('task definition mmm-dev-', "task definition mmm-$short-")
    $dst = Join-Path $ecsDst $j.Name
    $have = if (Test-Path $dst) { [IO.File]::ReadAllText($dst) } else { $null }
    if ($have -eq $want) { continue }
    if ($Check) { Write-Host "DIFFERS  ecs\$t\$($j.Name)" -ForegroundColor Red; $diffs++ }
    else { [IO.File]::WriteAllText($dst, $want, (New-Object Text.UTF8Encoding $false)); Write-Host "written  ecs\$t\$($j.Name)" }
  }

  # shared files removed from dev must disappear from the copies too
  Get-ChildItem $dir -File -Filter *.tf | Where-Object { $perEnv -notcontains $_.Name -and -not (Test-Path (Join-Path $source $_.Name)) } | ForEach-Object {
    if ($Check) { Write-Host "EXTRA    $t\$($_.Name)" -ForegroundColor Red; $diffs++ }
    else { Remove-Item $_.FullName; Write-Host "removed  $t\$($_.Name)" }
  }
}

if ($Check) {
  if ($diffs -gt 0) { Write-Host "$diffs file(s) out of sync - run .\scripts\sync-environments.ps1" -ForegroundColor Red; exit 1 }
  Write-Host "staging and prod use the same code as dev ($($shared.Count) shared files)" -ForegroundColor Green
}
