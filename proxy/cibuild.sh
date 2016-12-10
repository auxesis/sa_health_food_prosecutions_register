#!/bin/sh

set -e
set -x

wget https://releases.hashicorp.com/terraform/0.7.13/terraform_0.7.13_linux_amd64.zip
unzip terraform_0.7.13_linux_amd64.zip

mkdir $(pwd)/bin
mv terraform bin
export PATH="$PATH:$(pwd)/bin"

# Remote configs
terraform remote config -backend=S3 -backend-config="bucket=$BUCKET" -backend-config="key=terraform.tfstate" -backend-config="region=us-east-1"

make plan

terraform remote push
