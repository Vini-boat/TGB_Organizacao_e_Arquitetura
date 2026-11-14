#!/bin/sh
# Instala e inicializa o Incus no Alpine 3.24 (VM incus-host). Rodar como root.
# Uso:  sh preparar-incus.sh [usuario]      (padrão: aluno)
# Pode rodar de novo sem estragar nada. Detalhes: docs/01-configuracao-ambiente.md, 1.6 e 1.7.
set -eu

USUARIO="${1:-aluno}"
[ "$(id -u)" -eq 0 ] || { echo "rode como root (su -)"; exit 1; }

echo "== Repositório community"
sed -i 's|^#\(.*/v[0-9.]*/community\)$|\1|' /etc/apk/repositories
grep -q '/community$' /etc/apk/repositories || { echo "linha do community não encontrada em /etc/apk/repositories"; exit 1; }
apk update
apk upgrade

echo "== Pacotes"
apk add incus incus-client lxcfs btrfs-progs losetup bash curl

echo "== cgroups v2"
grep -q '^rc_cgroup_mode=' /etc/rc.conf \
  && sed -i 's/^rc_cgroup_mode=.*/rc_cgroup_mode="unified"/' /etc/rc.conf \
  || echo 'rc_cgroup_mode="unified"' >> /etc/rc.conf

echo "== Serviços"
for s in cgroups dbus lxcfs incusd; do
  rc-update add "$s" default 2>/dev/null || true
  rc-service "$s" status >/dev/null 2>&1 || rc-service "$s" start
done
modprobe btrfs || true

if id "$USUARIO" >/dev/null 2>&1; then
  addgroup "$USUARIO" incus 2>/dev/null || true
  echo "Usuário $USUARIO no grupo incus (saia e entre no SSH de novo)."
fi

echo "== Aguardando o incusd"
incus admin waitready --timeout=60

if incus storage list -f csv 2>/dev/null | grep -q '^default,'; then
  echo "Incus já inicializado."
else
  echo "== incus admin init (btrfs em arquivo de 10 GiB + incusbr0)"
  incus admin init --auto --storage-backend btrfs --storage-create-loop 10 \
    || incus admin init --auto --storage-backend dir
fi

incus version
incus storage list
incus network list
echo "Pronto. Teste: incus launch images:alpine/3.24 teste && incus list"
