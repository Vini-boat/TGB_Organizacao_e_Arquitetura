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

# Só no lb1: tem o perfil etcd (3º voto) e por isso enxerga /srv/etcd/etcd-lb1.
if [ -f /srv/etcd/etcd-$(hostname) ]; then
    bash /srv/etcd/setup.sh
fi
