#!/bin/sh

set -e
set -x

#wget https://releases.hashicorp.com/terraform/0.7.13/terraform_0.7.13_linux_amd64.zip
#unzip terraform_0.7.13_linux_amd64.zip
#
#mkdir $(pwd)/bin
#mv terraform bin
export PATH="$PATH:$(pwd)/bin"

ls -lah

pwd

echo $0
echo $@
dirname $0

#make plan

#make apply
