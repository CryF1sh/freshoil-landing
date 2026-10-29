#!/usr/bin/env bash
# Подтягивает свежую версию из GitHub и публикует её.
# Использование: sudo bash deploy/update.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source /etc/freshoil.conf   # DOMAIN=..., записывается при setup.sh

BEFORE="$(git -C "$REPO_DIR" rev-parse HEAD)"
git -C "$REPO_DIR" pull --ff-only
AFTER="$(git -C "$REPO_DIR" rev-parse HEAD)"

bash "$REPO_DIR/deploy/publish.sh" "$DOMAIN"
bash "$REPO_DIR/deploy/install-snippets.sh" "$DOMAIN"
if [[ -f /etc/systemd/system/freshoil-mailer.service ]]; then
  systemctl restart freshoil-mailer
fi

if [[ "$BEFORE" != "$AFTER" || "${1:-}" == "--ping" ]]; then
  echo "==> Сообщаю поисковикам об обновлении (IndexNow)"
  bash "$REPO_DIR/deploy/indexnow.sh" "$DOMAIN" || true
fi
echo "✓ Сайт https://$DOMAIN обновлён"
