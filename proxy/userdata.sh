#!/bin/sh

apt-get update
apt-get upgrade -y
apt-get install tinyproxy -y

echo 'Allow 0.0.0.0/0' >> /etc/tinyproxy.conf

service tinyproxy restart

systemctl enable tinyproxy.service
