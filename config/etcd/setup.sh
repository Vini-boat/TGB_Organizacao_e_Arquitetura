#!/bin/bash
# Instala e liga o etcd deste contêiner com o arquivo /srv/etcd/etcd-<hostname>.
# Chamado pelo setup.sh do db (db1, db2) e do lb (só o lb1 tem o perfil etcd).
set -e
. /srv/etcd/etcd-$(hostname)   # ETCD_NAME, ETCD_DATA_DIR, ETCD_INITIAL_CLUSTER_STATE...

apt install -y etcd-server etcd-client curl

# O pacote sobe um etcd de um membro só, em outra pasta: para e apaga (a nossa é a "tgb").
systemctl stop etcd
find /var/lib/etcd -mindepth 1 -maxdepth 1 ! -name tgb -exec rm -rf {} +

ln -sf /srv/etcd/etcd-$(hostname) /etc/default/etcd

# Membro que entra num cluster já existente (db2): os outros aprovam a entrada antes.
if [ "$ETCD_INITIAL_CLUSTER_STATE" = existing ] && [ ! -d "$ETCD_DATA_DIR" ]; then
    etcdctl --endpoints=http://10.10.10.31:2379,http://10.10.10.11:2379 \
        member add "$ETCD_NAME" --peer-urls="$ETCD_INITIAL_ADVERTISE_PEER_URLS"
fi

systemctl enable etcd
systemctl start --no-block etcd

# O Patroni só funciona com o cluster na versão 3.4 (com 3.0 ele usa a API antiga /v3alpha).
echo "Esperando a maioria do etcd (o outro votante precisa subir também)..."
until curl -s 127.0.0.1:2379/version | grep -q '"etcdcluster":"3.4'; do sleep 2; done
etcdctl member list -w table
