<#
.SYNOPSIS
  Installs the WBD MMM DevOps prerequisite tools WITHOUT admin rights (per-user, portable).

.DESCRIPTION
  Downloads portable builds into $ToolsDir and adds them to the *user* PATH:
    Terraform, AWS CLI v2, Git (PortableGit, includes bash), GitHub CLI (gh), jq,
    tflint, Trivy, Python 3.12 (+ Checkov via pip), Node.js 22 LTS.
  Docker Desktop is NOT installed: it needs admin rights + WSL2. Images are built by
  GitHub Actions runners, so Docker is only needed for optional local image builds.

  Safe to re-run: tools that are already present are skipped.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\install-prereqs.ps1
#>
[CmdletBinding()]
param(
  [string]$ToolsDir = "$env:USERPROFILE\tools",
  [string]$PythonVersion = '3.12.10',
  [int]$NodeMajor = 22
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$bin = Join-Path $ToolsDir 'bin'
$dl  = Join-Path $ToolsDir 'downloads'
New-Item -ItemType Directory -Force -Path $bin, $dl | Out-Null

$pathEntries = @(
  $bin,
  (Join-Path $ToolsDir 'git\cmd'),
  (Join-Path $ToolsDir 'git\bin'),
  (Join-Path $ToolsDir 'awscli\Amazon\AWSCLIV2'),
  (Join-Path $ToolsDir 'gh\bin'),
  (Join-Path $ToolsDir 'node'),
  (Join-Path $ToolsDir 'python')
)

function Get-GitHubAsset([string]$Repo, [string]$Pattern) {
  $rel = Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'wbd-mmm-installer' }
  $asset = $rel.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
  if (-not $asset) { throw "No asset matching '$Pattern' in $Repo $($rel.tag_name)" }
  [pscustomobject]@{ Tag = $rel.tag_name; Name = $asset.name; Url = $asset.browser_download_url }
}

function Save-File([string]$Url, [string]$Name) {
  $path = Join-Path $dl $Name
  if (-not (Test-Path $path)) {
    Write-Host "    downloading $Url"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $path
  }
  $path
}

function Expand-Fresh([string]$Zip, [string]$Dest) {
  if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
  Expand-Archive -Path $Zip -DestinationPath $Dest -Force
}

function Install-Step([string]$Name, [string]$CheckPath, [scriptblock]$Action) {
  Write-Host "==> $Name"
  if ($CheckPath -and (Test-Path $CheckPath)) { Write-Host "    already installed ($CheckPath)"; return }
  try { & $Action; Write-Host "    OK" }
  catch { Write-Warning "    $Name failed: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- Terraform
Install-Step 'Terraform' (Join-Path $bin 'terraform.exe') {
  $v = (Invoke-RestMethod -UseBasicParsing 'https://checkpoint-api.hashicorp.com/v1/check/terraform').current_version
  $zip = Save-File "https://releases.hashicorp.com/terraform/$v/terraform_${v}_windows_amd64.zip" "terraform_$v.zip"
  $tmp = Join-Path $dl 'tf'; Expand-Fresh $zip $tmp
  Copy-Item (Join-Path $tmp 'terraform.exe') $bin -Force
}

# ---------------------------------------------------------------- AWS CLI v2
# Administrative install (/a) just extracts the MSI, so no admin rights are needed.
Install-Step 'AWS CLI v2' (Join-Path $ToolsDir 'awscli\Amazon\AWSCLIV2\aws.exe') {
  $msi = Save-File 'https://awscli.amazonaws.com/AWSCLIV2.msi' 'AWSCLIV2.msi'
  $target = Join-Path $ToolsDir 'awscli'
  $p = Start-Process msiexec.exe -ArgumentList @('/a', "`"$msi`"", '/qn', "TARGETDIR=`"$target`"") -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "msiexec exit code $($p.ExitCode)" }
}

# ---------------------------------------------------------------- Git (portable, includes bash)
Install-Step 'Git (PortableGit)' (Join-Path $ToolsDir 'git\cmd\git.exe') {
  $a = Get-GitHubAsset 'git-for-windows/git' '^PortableGit-.*-64-bit\.7z\.exe$'
  $exe = Save-File $a.Url $a.Name
  $p = Start-Process $exe -ArgumentList @('-y', "-o`"$(Join-Path $ToolsDir 'git')`"") -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "PortableGit extract exit code $($p.ExitCode)" }
}

# ---------------------------------------------------------------- GitHub CLI
Install-Step 'GitHub CLI (gh)' (Join-Path $ToolsDir 'gh\bin\gh.exe') {
  $a = Get-GitHubAsset 'cli/cli' '^gh_.*_windows_amd64\.zip$'
  $zip = Save-File $a.Url $a.Name
  Expand-Fresh $zip (Join-Path $ToolsDir 'gh')
}

# ---------------------------------------------------------------- jq
Install-Step 'jq' (Join-Path $bin 'jq.exe') {
  $a = Get-GitHubAsset 'jqlang/jq' '^jq-windows-amd64\.exe$'
  $exe = Save-File $a.Url $a.Name
  Copy-Item $exe (Join-Path $bin 'jq.exe') -Force
}

# ---------------------------------------------------------------- tflint
Install-Step 'tflint' (Join-Path $bin 'tflint.exe') {
  $a = Get-GitHubAsset 'terraform-linters/tflint' '^tflint_windows_amd64\.zip$'
  $zip = Save-File $a.Url $a.Name
  $tmp = Join-Path $dl 'tflint'; Expand-Fresh $zip $tmp
  Copy-Item (Join-Path $tmp 'tflint.exe') $bin -Force
}

# ---------------------------------------------------------------- Trivy
Install-Step 'Trivy' (Join-Path $bin 'trivy.exe') {
  $a = Get-GitHubAsset 'aquasecurity/trivy' '^trivy_.*_windows-64bit\.zip$'
  $zip = Save-File $a.Url $a.Name
  $tmp = Join-Path $dl 'trivy'; Expand-Fresh $zip $tmp
  Copy-Item (Join-Path $tmp 'trivy.exe') $bin -Force
}

# ---------------------------------------------------------------- Node.js LTS (zip)
Install-Step "Node.js $NodeMajor" (Join-Path $ToolsDir 'node\node.exe') {
  $rel = (Invoke-RestMethod -UseBasicParsing 'https://nodejs.org/dist/index.json') |
    Where-Object { $_.version -like "v$NodeMajor.*" } | Select-Object -First 1
  $name = "node-$($rel.version)-win-x64"
  $zip = Save-File "https://nodejs.org/dist/$($rel.version)/$name.zip" "$name.zip"
  $tmp = Join-Path $dl 'node'; Expand-Fresh $zip $tmp
  $dest = Join-Path $ToolsDir 'node'
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  Move-Item (Join-Path $tmp $name) $dest
}

# ---------------------------------------------------------------- Python (per-user install)
Install-Step "Python $PythonVersion" (Join-Path $ToolsDir 'python\python.exe') {
  $exe = Save-File "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe" "python-$PythonVersion-amd64.exe"
  $pyArgs = @('/quiet', 'InstallAllUsers=0', 'PrependPath=0', 'Include_test=0', 'Include_launcher=0', "TargetDir=`"$(Join-Path $ToolsDir 'python')`"")
  $p = Start-Process $exe -ArgumentList $pyArgs -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Python installer exit code $($p.ExitCode)" }
}

# ---------------------------------------------------------------- Checkov (pip)
# The pip-generated checkov.cmd needs a .py file association, which a per-user Python
# install does not register, so a wrapper in $bin calls python.exe explicitly.
Install-Step 'Checkov' (Join-Path $bin 'checkov.cmd') {
  $py = Join-Path $ToolsDir 'python\python.exe'
  if (-not (Test-Path $py)) { throw 'Python is not installed' }
  & $py -m pip install --quiet --no-warn-script-location --upgrade pip
  & $py -m pip install --quiet --no-warn-script-location checkov
  if ($LASTEXITCODE -ne 0) { throw "pip install checkov exit code $LASTEXITCODE" }
  $script = Join-Path $ToolsDir 'python\Scripts\checkov'
  Set-Content -Path (Join-Path $bin 'checkov.cmd') -Encoding ASCII -Value "@echo off`r`n`"$py`" `"$script`" %*"
}

# ---------------------------------------------------------------- PATH (user scope)
Write-Host '==> Updating user PATH'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ })
foreach ($e in $pathEntries) { if ($parts -notcontains $e) { $parts += $e } }
[Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
$env:Path = ($pathEntries + ($env:Path -split ';')) -join ';'

# ---------------------------------------------------------------- Verify
Write-Host "`n==> Installed versions"
$checks = [ordered]@{
  'terraform' = { terraform version | Select-Object -First 1 }
  'aws'       = { aws --version }
  'git'       = { git --version }
  'gh'        = { gh --version | Select-Object -First 1 }
  'jq'        = { jq --version }
  'tflint'    = { tflint --version | Select-Object -First 1 }
  'trivy'     = { trivy --version | Select-Object -First 1 }
  'node'      = { node --version }
  'python'    = { python --version }
  'checkov'   = { checkov --version }
  'docker'    = { docker --version }
}
foreach ($k in $checks.Keys) {
  try { $out = & $checks[$k] 2>&1; Write-Host ("  {0,-10} {1}" -f $k, ($out | Out-String).Trim()) }
  catch { Write-Host ("  {0,-10} NOT INSTALLED" -f $k) }
}
Write-Host "`nOpen a NEW terminal so the updated PATH is picked up."
