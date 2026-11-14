#!/bin/bash
apt update
apt install -y haproxy curl
ln -sf /srv/lb/haproxy.cfg /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl restart haproxy
