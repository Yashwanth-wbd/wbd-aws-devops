# Runbook: deploy a release

Pipeline details: [docs/09](../09-cicd-pipelines.md). Tags: [docs/07](../07-branching-and-release.md).

## Dev (automatic)

Merging to `main` builds changed apps (`api-ci`, `ui-ci`, `optimizer-ci`, `training-ci`, `publisher-ci`)
and `deploy.yml` deploys `sha-<7char>` to dev for the components that changed. Nothing to do; check
the run is green.

## Staging (release candidate)

1. Pick the commit on `main` whose dev deploy is green and tested.
2. `git tag v1.4.0-rc1 <commit> && git push origin v1.4.0-rc1`
3. Approve the `staging` environment in the `deploy` run (EY delivery lead).
4. The run copies dev images (same digest), runs the migration, deploys `api` and `ui`, updates
   SageMaker image pointers and the publisher Lambda, smoke-tests through the ALB, and writes the
   release record. Check the artifact in the run summary.
5. UAT / parallel run on staging. Fix → new commit → `-rc2`.

## Prod

Prerequisites: UAT sign-off, change ticket (CAB) approved, the rc tag on the **same commit** is
green in staging, no open SEV1/SEV2.

1. `git tag -a v1.4.0 -m "CHG0012345 MMM release 1.4.0" <same commit> && git push origin v1.4.0`
2. A WBD approver (not the tagger) approves the `prod` environment.
3. The run: Aurora cluster snapshot `mmm-prd-predeploy-v1-4-0-<run>` → migration task → ECS services →
   SageMaker pointers → publisher → smoke test → release record.
4. Watch for 30 minutes: dashboard `mmm-prd-platform`, alarms, `/ecs/mmm-prd/api` errors.
5. Close the change ticket with the release record (version, digests, task-definition revisions, approvers).

## Infrastructure (Terraform)

PR touching `infra/**` → plan for dev and staging in the PR → merge → `terraform.yml` applies
dev, then staging and prod after their approvals. Always edit `infra/environments/dev` and run
`.\scripts\sync-environments.ps1` before committing.

## If it fails

The run rolls back ECS services, SSM SageMaker image pointers and the publisher Lambda alias
`live` automatically (migrations are not reverted; expand-then-contract). See [rollback.md](rollback.md)
and [pipeline-failure.md](pipeline-failure.md).
