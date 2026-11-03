<#
.SYNOPSIS
  Scans the repository for committed secrets with Trivy, also when the repo sits on a network (UNC) share.

.DESCRIPTION
  The repo is copied to %TEMP% (without .terraform and .git) and scanned there, because Trivy
  does not reliably walk UNC paths on Windows. Exit code 1 means a secret was found.
  CI runs gitleaks / Trivy directly on the checkout (Step 11).

.EXAMPLE
  .\scripts\secret-scan.ps1
#>
[CmdletBinding()]
param(
  [string]$Path
)

$ErrorActionPreference = 'Stop'
if (-not $Path) { $Path = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..' }
$src = (Resolve-Path $Path).ProviderPath
$dst = Join-Path $env:TEMP 'mmm-secretscan'

if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
robocopy $src $dst /E /XD .terraform .git /NFL /NDL /NJH /NJS /NP | Out-Null

trivy fs --scanners secret --quiet --exit-code 1 $dst
$code = $LASTEXITCODE
if ($code -eq 0) { Write-Host "Secret scan: no secrets found in $src" -ForegroundColor Green }
exit $code
