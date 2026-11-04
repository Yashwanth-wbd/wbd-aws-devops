# Runbook: model rollback

MMM models are registered in Databricks Unity Catalog as `<catalog>.models.mmm_<bu>`; workers
load the version behind the **`production`** alias, so a rollback moves the alias – no redeploy.
Full flow: [docs/10 §7](../10-data-platform-and-model-governance.md#7-model-governance-model-governanceyml).

## When

Planners report implausible ROI curves / recommendations for one BU after a promotion, a
governance metric degrades, or the data team asks for it.

## Steps

1. Confirm which version is live and which one was before (the promotion stored it):
   tags `promoted_by` and `previous_production_version` on the current version (Databricks UI or MLflow API).
2. Start the rollback (needs the `<env>-model-promotion` approval by a WBD model approver who did not request it):
   ```bash
   gh workflow run model-governance.yml -f environment=prod -f action=rollback -f business_unit=streaming
   ```
3. Approve in GitHub → the run moves `production` to `previous_production_version` and tags the
   bad version.
4. Workers pick up the alias on the next model load (cache TTL of the app; force a new
   deployment of `whatif-worker` and `optimizer-worker` if the app caches the model for the task lifetime):
   ```bash
   for s in whatif-worker optimizer-worker; do aws ecs update-service --cluster $P-ecs --service $P-$s --force-new-deployment; done
   ```
5. Verify: worker log shows the expected model version for the BU; a known what-if returns the
   previous results.
6. Scenarios created with the bad model: the app team lists them (model version is stored with
   each scenario); planners re-run the important ones. Approved scenarios in the WORM bucket stay
   as they are (audit) – annotate, do not delete.

## If GitHub or the governance workflow is unavailable

A Databricks admin moves the alias in the UI (`Set alias production` on the previous version)
under an incident ticket, and the workflow's audit tags are added afterwards.
