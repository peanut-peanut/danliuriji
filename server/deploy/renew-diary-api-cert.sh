#!/usr/bin/env sh
set -eu

CERT_DIR=/etc/letsencrypt/live/diary-api.peanutwcx.xyz
TARGET_DIR=/opt/chenxu-space/nginx/ssl/diary-api
mkdir -p "$TARGET_DIR"
install -m 644 "$CERT_DIR/fullchain.pem" "$TARGET_DIR/fullchain.pem"
install -m 600 "$CERT_DIR/privkey.pem" "$TARGET_DIR/privkey.pem"
docker exec chenxu-space-nginx nginx -t
docker exec chenxu-space-nginx nginx -s reload
