<#
.SYNOPSIS
  Scaffolds a Terraform module under infra/modules/<Name> with the project's standard files.

.DESCRIPTION
  Creates versions.tf (Terraform >= 1.6, AWS provider ~> 5.60), main.tf, variables.tf,
  outputs.tf and README.md. Existing modules are never overwritten.

.EXAMPLE
  .\scripts\new-module.ps1 -Name sqs -Step 6 -Purpose "FIFO job queue + DLQ" -Resources "SQS FIFO queue","SQS DLQ"
  .\scripts\new-module.ps1 -Name edge -Step 8 -Purpose "..." -Resources "..." -ProviderAliases us_east_1
  .\scripts\new-module.ps1 -Name secrets -Step 5 -Purpose "..." -Resources "..." -ExtraProviders random
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$Name,
  [Parameter(Mandatory)] [string]$Step,
  [Parameter(Mandatory)] [string]$Purpose,
  [Parameter(Mandatory)] [string[]]$Resources,
  [string[]]$ProviderAliases = @(),
  [ValidateSet('random', 'archive')] [string[]]$ExtraProviders = @(),
  [string]$ModulesDir = ''
)

$ErrorActionPreference = 'Stop'
if (-not $ModulesDir) { $ModulesDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\infra\modules' }
$dir = Join-Path $ModulesDir $Name
if (Test-Path $dir) { Write-Host "skip  $Name (already exists)"; return }
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Lf([string]$File, [string[]]$Lines) {
  [IO.File]::WriteAllText((Join-Path $dir $File), (($Lines -join "`n") + "`n"), $utf8)
}

$providerVersions = @{ random = '~> 3.6'; archive = '~> 2.4' }

$v = @('terraform {', '  required_version = ">= 1.6"', '', '  required_providers {', '    aws = {',
  '      source  = "hashicorp/aws"', '      version = "~> 5.60"')
if ($ProviderAliases.Count -gt 0) {
  $aliases = ($ProviderAliases | ForEach-Object { "aws.$_" }) -join ', '
  $v += "      configuration_aliases = [$aliases]"
}
$v += '    }'
foreach ($p in $ExtraProviders) {
  $v += @("    $p = {", "      source  = ""hashicorp/$p""", "      version = ""$($providerVersions[$p])""", '    }')
}
$v += @('  }', '}')
Write-Lf 'versions.tf' $v

$m = @("# $Name module - $Purpose", "# Implemented in Step $Step. Planned resources:")
$m += $Resources | ForEach-Object { "#   - $_" }
Write-Lf 'main.tf' $m
Write-Lf 'variables.tf' @("# Inputs for the $Name module are added in Step $Step.")
Write-Lf 'outputs.tf'   @("# Outputs for the $Name module are added in Step $Step.")

$r = @("# $Name", '', $Purpose, '', "**Status:** skeleton - implemented in Step $Step.", '', '## Planned resources', '')
$r += $Resources | ForEach-Object { "- $_" }
if ($ProviderAliases.Count -gt 0) {
  $r += @('', '## Provider aliases', '', 'The calling stack must pass these providers:', '')
  $r += $ProviderAliases | ForEach-Object { "- ``aws.$_``" }
}
$r += @('', '## Inputs and outputs', '', "Documented here when the module is implemented in Step $Step.")
Write-Lf 'README.md' $r

if (Get-Command terraform -ErrorAction SilentlyContinue) { terraform fmt $dir | Out-Null }
Write-Host "create $Name"
