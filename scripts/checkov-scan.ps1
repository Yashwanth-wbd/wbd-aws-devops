<#
.SYNOPSIS
  Runs Checkov on a Terraform folder, also when the repo sits on a network (UNC) share.

.DESCRIPTION
  Checkov fails on UNC paths on Windows ("path is on mount ..."), so the folder's
  Terraform files are copied to %TEMP% and scanned there. CI runs Checkov directly.

.EXAMPLE
  .\scripts\checkov-scan.ps1 -Path .\infra\bootstrap
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$Path,
  [string]$Python = "$env:USERPROFILE\tools\python\python.exe"
)

$ErrorActionPreference = 'Stop'
$src = (Resolve-Path $Path).ProviderPath
$dst = Join-Path $env:TEMP ("mmm-checkov\" + (Split-Path $src -Leaf))

if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
New-Item -ItemType Directory -Force -Path $dst | Out-Null
robocopy $src $dst *.tf *.tfvars *.hcl /S /XD .terraform /NFL /NDL /NJH /NJS /NP | Out-Null

Push-Location $dst
try {
  & $Python (Join-Path (Split-Path $Python) 'Scripts\checkov') -d . --framework terraform --compact --quiet
  $code = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($code -eq 0) { Write-Host "Checkov: no failed checks in $src" -ForegroundColor Green }
exit $code
