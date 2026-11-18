#!/bin/bash
apt update
apt install -y python3-fastapi python3-uvicorn python3-jinja2 python3-psycopg2
systemctl enable --now /srv/app/app.service
