"""One-time database setup, run as the migrate task when enable_db_bootstrap = true.

Connects to RDS Proxy as the admin user with an IAM token and creates the migration and app
users. Their passwords are generated here and written only to their Secrets Manager secrets
(RDS Proxy logs in to the database with them; clients keep using IAM tokens).
Safe to run again: existing users are kept and their password is re-synced from the secret.
"""
import json
import os
import secrets
import subprocess
import sys

subprocess.check_call(
    [sys.executable, "-m", "pip", "install", "--quiet", "--no-cache-dir", "--target", "/tmp/py",
     "psycopg[binary]==3.2.3", "boto3==1.35.90"]
)
sys.path.insert(0, "/tmp/py")

import boto3  # noqa: E402
import psycopg  # noqa: E402
from psycopg import sql  # noqa: E402

region = os.environ["AWS_REGION"]
host = os.environ["DB_HOST"]
db_name = os.environ["DB_NAME"]
admin_user = os.environ["DB_ADMIN_USER"]
users = {
    "mmm_migrator": os.environ["MIGRATE_SECRET_ID"],
    "mmm_app": os.environ["APP_SECRET_ID"],
}

sm = boto3.client("secretsmanager", region_name=region)


def password_for(user, secret_id):
    try:
        current = json.loads(sm.get_secret_value(SecretId=secret_id)["SecretString"])
        if current.get("username") == user and current.get("password"):
            return current["password"]
    except sm.exceptions.ResourceNotFoundException:
        pass
    password = secrets.token_urlsafe(32)
    sm.put_secret_value(SecretId=secret_id, SecretString=json.dumps({"username": user, "password": password}))
    print(f"{user}: new password stored in its secret")
    return password


token = boto3.client("rds", region_name=region).generate_db_auth_token(host, 5432, admin_user, region)

with psycopg.connect(host=host, port=5432, dbname=db_name, user=admin_user, password=token,
                     sslmode="require", autocommit=True) as conn:
    cur = conn.cursor()
    cur.execute("CREATE EXTENSION IF NOT EXISTS pgaudit")
    cur.execute("SELECT 1 FROM pg_roles WHERE rolname = 'rds_pgaudit'")
    if not cur.fetchone():
        cur.execute("CREATE ROLE rds_pgaudit")

    for user, secret_id in users.items():
        password = password_for(user, secret_id)
        cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (user,))
        verb = "ALTER" if cur.fetchone() else "CREATE"
        cur.execute(sql.SQL(verb + " ROLE {} LOGIN PASSWORD {}").format(sql.Identifier(user), sql.Literal(password)))
        cur.execute(sql.SQL("GRANT rds_iam TO {}").format(sql.Identifier(user)))
        print(f"{user}: {verb.lower()}d")

    # PostgreSQL 16: the admin must be able to SET ROLE to the new owner.
    cur.execute(sql.SQL("GRANT {} TO CURRENT_USER WITH SET TRUE").format(sql.Identifier("mmm_migrator")))
    cur.execute(sql.SQL("ALTER DATABASE {} OWNER TO {}").format(sql.Identifier(db_name), sql.Identifier("mmm_migrator")))
    cur.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(sql.Identifier(db_name), sql.Identifier("mmm_app")))

print("DB BOOTSTRAP DONE")
