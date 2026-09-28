#!/usr/bin/env bash

echo "AWS_ACCESS_KEY_ID=AKIA$(cat /dev/urandom | tr -dc 'A-Z2-7' | head -c 16)"
echo "AWS_SECRET_ACCESS_KEY=$(cat /dev/urandom | tr -dc 'A-Za-z0-9/+' | head -c 40)"

