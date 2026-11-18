#!/bin/bash
# Instala e liga PostgreSQL 16 + Patroni + etcd. Os arquivos de cada contêiner
# vêm do hostname: /srv/etcd/etcd-<nome> e /srv/db/patroni-<nome>.yml.
set -e
H=$(hostname)

apt update
apt install -y postgresql-16 patroni curl

# O pacote cria e liga um banco padrão (16/main). Quem cria e liga o banco é o Patroni.
pg_dropcluster 16 main --stop 2>/dev/null || true
systemctl disable --now postgresql

bash /srv/etcd/setup.sh

ln -sf /srv/db/patroni-$H.yml /etc/patroni/16-main.yml
systemctl enable patroni@16-main
systemctl restart patroni@16-main

echo "Esperando o PostgreSQL subir (no db2 inclui copiar os dados do primário)..."
until curl -sf 127.0.0.1:8008/health > /dev/null; do sleep 2; done
patronictl -c /etc/patroni/16-main.yml list
