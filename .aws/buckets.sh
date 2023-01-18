#!/usr/bin/env bash
set -x
# awslocal s3 mb s3://test-static.quizzop.com 
aws --endpoint-url=http://127.0.0.1:4566 s3api create-bucket --bucket dev-discovery --create-bucket-configuration LocationConstraint=ap-south-1
set +x