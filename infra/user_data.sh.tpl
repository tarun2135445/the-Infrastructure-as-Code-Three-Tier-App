#!/bin/bash
###############################################################################
# Cloud-init script for the app tier.
#
# 1. Update OS packages.
# 2. Install Python + the AWS CLI (Amazon Linux 2023 ships an older one).
# 3. Pull the DB credentials JSON out of Secrets Manager using the
#    instance role — never bake them into the AMI or user-data.
# 4. Drop a tiny Flask app to /opt/app and run it under gunicorn via
#    systemd so it restarts on crash and on reboot.
# 5. Tell systemd to start the app.
#
# Anything echoed here lands in /var/log/cloud-init-output.log on the
# instance. Tail it via SSM if the target group never goes healthy:
#   aws ssm start-session --target <instance-id>
#   sudo tail -f /var/log/cloud-init-output.log
###############################################################################
set -euxo pipefail

APP_PORT="${app_port}"
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_NAME="${db_name}"
SECRET_ARN="${secret_arn}"
REGION="${region}"

dnf -y update
dnf -y install python3-pip python3-devel gcc postgresql15 jq

python3 -m pip install --quiet --upgrade pip
python3 -m pip install --quiet flask gunicorn psycopg2-binary boto3

install -d -m 0755 /opt/app
cat >/opt/app/app.py <<'PYEOF'
import json
import os
import socket
from datetime import datetime, timezone

import boto3
import psycopg2
from flask import Flask, jsonify
from urllib.request import urlopen

app = Flask(__name__)

REGION     = os.environ["AWS_REGION"]
SECRET_ARN = os.environ["DB_SECRET_ARN"]
DB_HOST    = os.environ["DB_HOST"]
DB_PORT    = int(os.environ["DB_PORT"])
DB_NAME    = os.environ["DB_NAME"]

_creds = None
def db_credentials():
    global _creds
    if _creds is None:
        sm = boto3.client("secretsmanager", region_name=REGION)
        _creds = json.loads(sm.get_secret_value(SecretId=SECRET_ARN)["SecretString"])
    return _creds

def imds(path, timeout=1):
    # IMDSv2: get a token, then read the metadata path.
    try:
        token = urlopen(
            _req("PUT", "http://169.254.169.254/latest/api/token",
                 {"X-aws-ec2-metadata-token-ttl-seconds": "60"}),
            timeout=timeout,
        ).read().decode()
        return urlopen(
            _req("GET", f"http://169.254.169.254/latest/meta-data/{path}",
                 {"X-aws-ec2-metadata-token": token}),
            timeout=timeout,
        ).read().decode()
    except Exception:
        return "unknown"

def _req(method, url, headers):
    from urllib.request import Request
    r = Request(url, method=method)
    for k, v in headers.items():
        r.add_header(k, v)
    return r

@app.get("/health")
def health():
    # Liveness only — don't let DB hiccups deregister the whole fleet.
    return ("ok", 200)

@app.get("/")
def index():
    info = {
        "service":     "aws-portfolio app",
        "hostname":    socket.gethostname(),
        "instance_id": imds("instance-id"),
        "az":          imds("placement/availability-zone"),
        "now_utc":     datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "db":          {"host": DB_HOST, "name": DB_NAME, "status": "unknown"},
    }
    try:
        creds = db_credentials()
        with psycopg2.connect(
            host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
            user=creds["username"], password=creds["password"],
            connect_timeout=3,
        ) as conn, conn.cursor() as cur:
            cur.execute("SELECT version(), now();")
            version, server_time = cur.fetchone()
            info["db"]["status"]      = "connected"
            info["db"]["version"]     = version.split(" on ")[0]
            info["db"]["server_time"] = server_time.isoformat(timespec="seconds")
    except Exception as e:  # noqa: BLE001
        info["db"]["status"] = "error"
        info["db"]["error"]  = str(e)
    return jsonify(info)
PYEOF

cat >/etc/systemd/system/app.service <<EOF
[Unit]
Description=AWS portfolio app
After=network-online.target
Wants=network-online.target

[Service]
Environment=AWS_REGION=$REGION
Environment=DB_SECRET_ARN=$SECRET_ARN
Environment=DB_HOST=$DB_HOST
Environment=DB_PORT=$DB_PORT
Environment=DB_NAME=$DB_NAME
WorkingDirectory=/opt/app
ExecStart=/usr/local/bin/gunicorn --bind 0.0.0.0:$APP_PORT --workers 2 --timeout 30 app:app
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now app.service
