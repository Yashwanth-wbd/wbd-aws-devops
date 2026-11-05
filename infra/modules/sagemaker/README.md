# sagemaker

Execution role (and, for training, the Model Registry groups) of one family of SageMaker jobs.
Jobs themselves are started by Step Functions (`createProcessingJob.sync`, `createTrainingJob.sync`);
nothing runs when idle, so there is no endpoint or notebook.

**Status:** implemented (v2 architecture). Used twice: `optimization` (always) and `training`
(`enable_data_platform`).

## What it creates

| Resource | Notes |
|---|---|
| `aws_iam_role` `<prefix>-sagemaker-<name>` | Trusted by `sagemaker.amazonaws.com`; permission boundary. Policy: read `read_bucket_arns`, write `write_bucket_arns`, the bucket keys, pull from `ecr_repository_arns`, job logs and metrics, and the volume key |
| `aws_sagemaker_model_package_group` per business unit | `<prefix>-<bu>` (only when `model_package_groups` is set). The model-refresh state machine registers each retrained model here as `PendingManualApproval` |
| EventBridge rule + SNS target | Model package state changes (registered, approved, rejected) → `notification_topic_arn` |

Images are not set here: the state machines read the current image URI from SSM
(`/mmm/<env_short>/images/sagemaker-*`), which `deploy.yml` updates per release.

## Inputs

`name_prefix`, `name`, `read_bucket_arns`, `write_bucket_arns`, `data_kms_key_arns`,
`volume_kms_key_arn` (kms `sagemaker`), `ecr_repository_arns`, `model_package_groups` ([]),
`notification_topic_arn`, `permissions_boundary_arn`, `tags`.

## Outputs

`role_arn`, `role_name`, `model_package_group_names`, `model_package_group_arns`.
