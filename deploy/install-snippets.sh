#!/usr/bin/env bash
# Подключает дополнительные куски конфига nginx (редирект www, приём заявок)
# к конфигу сайта и перезагружает nginx. Безопасно запускать повторно.
# Использование: sudo bash deploy/install-snippets.sh example.by
set -euo pipefail

DOMAIN="${1:?Укажите домен}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF="/etc/nginx/sites-available/${DOMAIN}"
INCLUDE_LINE="include /etc/nginx/snippets/freshoil-*.conf;"

mkdir -p /etc/nginx/snippets
cp "$REPO_DIR/deploy/nginx-seo.conf" /etc/nginx/snippets/freshoil-seo.conf
if [[ -f /etc/systemd/system/freshoil-mailer.service ]]; then
  cp "$REPO_DIR/deploy/mailer/nginx-api.conf" /etc/nginx/snippets/freshoil-api.conf
fi

cp "$CONF" "$CONF.bak"
if ! grep -qF "$INCLUDE_LINE" "$CONF"; then
  # Вставляем include после строки root в блоке сайта (certbot оставляет её одну)
  sed -i "/^\s*root \/var\/www\/${DOMAIN//./\\.};/a\\    ${INCLUDE_LINE}" "$CONF"
fi
if ! nginx -t 2>/dev/null; then
  cp "$CONF.bak" "$CONF"
  rm -f /etc/nginx/snippets/freshoil-seo.conf
  echo "✗ nginx не принял новые настройки, вернул как было:"; nginx -t; exit 1
fi
systemctl reload nginx
