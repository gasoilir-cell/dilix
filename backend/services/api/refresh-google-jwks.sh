#!/bin/bash
# این اسکریپت را روی ماشین محلی خود (نه سرور) اجرا کنید:
# bash refresh-google-jwks.sh
#
# یا مستقیم این دستور را روی ماشین محلی:
# JWKS=$(curl -s https://www.googleapis.com/oauth2/v3/certs) && ssh root@185.55.226.250 "echo '$JWKS' > /var/www/dilix-api/google-jwks-cache.json && systemctl restart dilix-api"
echo "این اسکریپت باید از ماشین محلی اجرا شود، نه سرور"
