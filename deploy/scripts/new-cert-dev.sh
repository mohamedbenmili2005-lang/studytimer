#!/bin/sh
# Certificat auto-signe pour tester HTTPS en local. En production : Let's Encrypt (certbot) vers deploy/certs.
mkdir -p deploy/certs
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout deploy/certs/privkey.pem -out deploy/certs/fullchain.pem \
  -subj "/CN=localhost"
