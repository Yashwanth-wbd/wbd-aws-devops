# Runbook: model rollback

Approved response curves live in `s3://<models>/curves/<bu>/` (written by `model-governance.yml`
**promote**). The API and SageMaker optimizer read those objects; registry state is in the SageMaker
Model Registry package group `mmm-<env_short>-<bu>`. Full flow:
[docs/10 §7](../10-data-platform-and-model-governance.md#7-model-governance-model-governanceyml).

## When

Planners report implausible ROI curves / recommendations for one BU after a promotion, governance
metrics fail, or the data team asks for it.

## Steps

1. Confirm which model package version is approved and which was previous (tag
   `previous_approved_version` on the package, or the promotion audit in GitHub).
2. Start the rollback (needs `<env>-model-promotion` approval by a WBD model approver who did not
   request it):
   ```bash
   gh workflow run model-governance.yml -f environment=prod -f action=rollback -f business_unit=streaming
   ```
   Optional: `-f version=<package-version>` if not using `previous_approved_version`.
3. Approve in GitHub → the run re-copies the previous version's curves to `curves/<bu>/`, rejects
   the bad package version, and updates governance tags.
4. New what-if and optimization runs pick up the curves from S3 immediately. If the API caches
   curves in memory, force `aws ecs update-service --cluster $P-ecs --service $P-api --force-new-deployment`.
5. Verify: a known what-if returns the previous results; `aws s3 ls s3://<models-bucket>/curves/streaming/`
   shows the expected `_model_package.json`.
6. Scenarios created with the bad model: the app team lists them; planners re-run important ones.
   Approved scenarios in the WORM bucket stay as they are (audit) – annotate, do not delete.

## If GitHub or the governance workflow is unavailable

Under an incident ticket, a user with the `gha-model-approve` role (or break-glass) can run
`scripts/model_governance.py rollback` locally with OIDC credentials, or manually copy the previous
curves in S3 and set package status to **Rejected** in the SageMaker console – then reconcile tags
when the workflow is back.
