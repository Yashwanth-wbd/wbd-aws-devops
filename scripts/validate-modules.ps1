<#
.SYNOPSIS
  Runs terraform fmt, init (no backend), validate and tflint on every module (or a subset).

.DESCRIPTION
  No AWS credentials are needed. Providers are cached in %USERPROFILE%\.terraform.d\plugin-cache
  so each module does not download them again. Exits non-zero if any module fails.

.EXAMPLE
  .\scripts\validate-modules.ps1                 # all modules
  .\scripts\validate-modules.ps1 -Name sqs,rds   # selected modules
#>
[CmdletBinding()]
param(
  [string[]]$Name = @(),
  [string]$ModulesDir = ''
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root  = (Resolve-Path (Join-Path $scriptDir '..')).ProviderPath
if (-not $ModulesDir) { $ModulesDir = Join-Path $root 'infra\modules' }
$cache = Join-Path $env:USERPROFILE '.terraform.d\plugin-cache'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$env:TF_PLUGIN_CACHE_DIR = $cache
$env:TF_IN_AUTOMATION = '1'

$dirs = Get-ChildItem -Directory (Resolve-Path $ModulesDir) | Where-Object { $Name.Count -eq 0 -or $Name -contains $_.Name }
$failed = @()

foreach ($d in $dirs) {
  # A module that declares configuration_aliases cannot be validated on its own; validate a temp
  # copy where the aliases are real (empty) provider configurations instead.
  $workDir = $d.FullName
  $tfText  = (Get-ChildItem $d.FullName -Filter *.tf | Get-Content -Raw) -join "`n"
  $aliasMatch = [regex]::Match($tfText, 'configuration_aliases\s*=\s*\[([^\]]*)\]')
  if ($aliasMatch.Success) {
    $workDir = Join-Path $env:TEMP "mmm-validate\$($d.Name)"
    if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
    robocopy $d.FullName $workDir /E /XD .terraform /NFL /NDL /NJH /NJS /NP | Out-Null
    foreach ($f in Get-ChildItem $workDir -Filter *.tf) {
      $t = [IO.File]::ReadAllText($f.FullName)
      [IO.File]::WriteAllText($f.FullName, ($t -replace '(?m)^\s*configuration_aliases\s*=.*$', ''))
    }
    $providers = foreach ($a in ($aliasMatch.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
      $p = $a.Split('.')
      "provider `"$($p[0])`" {`n  alias = `"$($p[1])`"`n}`n"
    }
    [IO.File]::WriteAllText((Join-Path $workDir '_validate_providers.tf'), ($providers -join "`n"))
    terraform fmt -recursive $workDir | Out-Null
  }

  Push-Location $workDir
  try {
    $steps = [ordered]@{
      fmt      = { terraform fmt -check -recursive -no-color $d.FullName }
      init     = { terraform init -backend=false -input=false -no-color }
      validate = { terraform validate -no-color }
      tflint   = { tflint --config="$root\.tflint.hcl" --no-color }
    }
    $result = 'ok'
    foreach ($s in $steps.Keys) {
      $out = & $steps[$s] 2>&1
      if ($LASTEXITCODE -ne 0) { $result = "FAILED at $s"; Write-Host ($out | Out-String); break }
    }
  } finally {
    Pop-Location
  }
  Write-Host ("{0,-20} {1}" -f $d.Name, $result)
  if ($result -ne 'ok') { $failed += $d.Name }
}

if ($failed.Count -gt 0) { Write-Host "`nFailed: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "`nAll $($dirs.Count) modules passed." -ForegroundColor Green
