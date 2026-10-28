#!/usr/bin/env bash
# Подтягивает свежую версию из GitHub и публикует её.
# Использование: sudo bash deploy/update.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source /etc/freshoil.conf   # DOMAIN=..., записывается при setup.sh

git -C "$REPO_DIR" pull --ff-only
bash "$REPO_DIR/deploy/publish.sh" "$DOMAIN"
if [[ -f /etc/systemd/system/freshoil-mailer.service ]]; then
  cp "$REPO_DIR/deploy/mailer/nginx-api.conf" /etc/nginx/snippets/freshoil-api.conf
  systemctl restart freshoil-mailer
  nginx -t 2>/dev/null && systemctl reload nginx
fi
echo "✓ Сайт https://$DOMAIN обновлён"
