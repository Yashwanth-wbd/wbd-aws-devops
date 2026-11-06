# 00 – Prerequisite tools

## Tools

| Tool | Minimum | Installed here | Verify | Used for |
|---|---|---|---|---|
| Terraform | 1.6 | 1.17.1 | `terraform version` | All infrastructure |
| AWS CLI v2 | latest | 2.39.3 | `aws --version` | SSO login, bootstrap, validation commands |
| Git | latest | 2.56.0 (PortableGit, includes Git Bash) | `git --version` | Source control; Git Bash runs the `scripts/*.sh` files |
| GitHub CLI | latest | 2.103.3 | `gh --version` | Create GitHub Environments, variables, protection rules |
| jq | latest | 1.8.2 | `jq --version` | JSON handling in scripts |
| tflint | latest | 0.65.0 | `tflint --version` | Terraform lint (also runs in CI) |
| Checkov | latest | 3.4.3 | `checkov --version` | Terraform security scan (also runs in CI) |
| Trivy | latest | 0.76.1 | `trivy --version` | Image and IaC vulnerability scan (also runs in CI) |
| Python | 3.12 | 3.12.10 | `python --version` | Checkov, model-governance script |
| Node.js | 22 | 22.23.4 | `node --version` | Optional: run `ui-ci.yml` checks locally (`apps/ui`) |
| Docker | latest | **not installed** | `docker version` | Optional: build images locally |

## Installing

The machine has no admin rights and no package manager, so
[`scripts/install-prereqs.ps1`](../scripts/install-prereqs.ps1) installs portable copies:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-prereqs.ps1
```

- Installs into `%USERPROFILE%\tools` and adds the folders to the **user** PATH.
- Already-installed tools are skipped, so it is safe to re-run.
- Open a **new** terminal afterwards so the PATH change applies.

## Docker

Docker Desktop needs admin rights and WSL2, so it cannot be installed with this script.
It is **not required**: images are built, scanned and pushed by GitHub Actions on
GitHub-hosted runners. Ask the desktop team to install Docker Desktop only if you need to
build images locally.

## Corporate proxy / TLS inspection

If `terraform init`, `aws`, `pip` or `npm` fail with *"unable to get local issuer
certificate"*, export the corporate root CA bundle:

```powershell
# add actual value
$ca = "C:\certs\wbd-root-ca.pem"
[Environment]::SetEnvironmentVariable('AWS_CA_BUNDLE', $ca, 'User')
[Environment]::SetEnvironmentVariable('REQUESTS_CA_BUNDLE', $ca, 'User')
[Environment]::SetEnvironmentVariable('NODE_EXTRA_CA_CERTS', $ca, 'User')
[Environment]::SetEnvironmentVariable('SSL_CERT_FILE', $ca, 'User')
```

## Accounts and access to request (Stage 0)

| Access | From | Needed for |
|---|---|---|
| AWS SSO for dev, staging, prod | WBD Cloud Platform team | Bootstrap and validation |
| GitHub org: create repo, Environments, variables | WBD GitHub admins | Pipelines |
| Okta OIDC Web apps per environment (client ID + secret) | WBD Identity team | Planner login (ALB `authenticate-oidc` → Okta) |
| Databricks workspace + service principals | WBD Databricks admins | Data platform (Step 13) and bundle deploy |
| Splunk HEC endpoint + token | WBD Splunk team | Log shipping (Step 9) |
| CAB process + named approvers | WBD change management | Prod releases |

The full list of open values is in [01-client-inputs-tracker.md](01-client-inputs-tracker.md).
