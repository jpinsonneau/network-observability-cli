#!/bin/bash
set -euo pipefail

echo "OpenSSL: $(openssl version)"
echo "nginx: $(nginx -v 2>&1)"

if ! nginx -t 2>&1; then
  echo "nginx config test failed — OpenSSL in this image may lack kTLS (need OpenSSL 3.x)" >&2
  exit 1
fi

exec nginx -g 'daemon off;'
