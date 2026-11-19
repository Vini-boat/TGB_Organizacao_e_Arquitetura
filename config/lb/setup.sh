#!/bin/bash
set -e
apt update
apt install -y haproxy keepalived curl
ln -sf /srv/lb/haproxy.cfg /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl restart haproxy
ln -sf /srv/lb/keepalived.conf /etc/keepalived/keepalived.conf
keepalived -t -f /etc/keepalived/keepalived.conf
systemctl enable keepalived
systemctl restart keepalived
