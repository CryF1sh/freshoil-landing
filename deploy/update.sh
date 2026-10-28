#!/usr/bin/env bash
# Подтягивает свежую версию из GitHub и публикует её.
# Использование: sudo bash deploy/update.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source /etc/freshoil.conf   # DOMAIN=..., записывается при setup.sh

git -C "$REPO_DIR" pull --ff-only
bash "$REPO_DIR/deploy/publish.sh" "$DOMAIN"
echo "✓ Сайт https://$DOMAIN обновлён"
