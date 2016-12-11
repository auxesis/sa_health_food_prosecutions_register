#!/bin/sh

set -e
set -x

# Ensure we're in the same directory as this script
cd $(dirname $0)

# Set up Terraform
wget https://releases.hashicorp.com/terraform/0.7.13/terraform_0.7.13_linux_amd64.zip
unzip terraform_0.7.13_linux_amd64.zip
mkdir $(pwd)/bin
mv terraform bin
export PATH="$PATH:$(pwd)/bin"

# Remote configs
terraform remote config -backend=S3 -backend-config="bucket=$BUCKET" -backend-config="key=terraform.tfstate" -backend-config="region=us-east-1"
terraform remote pull

make apply

terraform remote push
