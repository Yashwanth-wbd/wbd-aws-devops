"""Seed handler: lets Terraform create the function before the first app deploy (deploy.yml)."""

import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    logger.info("seed handler called - waiting for the first deploy: %s", json.dumps(event)[:2000])
    return {"status": "SEED", "message": "replaced by the first deploy of this function"}
