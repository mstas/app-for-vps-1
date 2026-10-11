#!/usr/bin/env bash
# Первичное получение HTTPS-сертификата Let's Encrypt.
#
#   bash scripts/init-https.sh                 # по IP сервера (определится сам)
#   bash scripts/init-https.sh 203.0.113.10    # по указанному IP
#   bash scripts/init-https.sh demo.example.com you@mail.com   # по домену
#
# Сертификат получает certbot в режиме standalone (сам слушает порт 80,
# nginx на это время остановлен). Дальше продление идёт через webroot
# контейнером certbot из docker-compose.prod.yml, без остановки nginx.
# Для IP выдаётся сертификат на 6 дней (профиль shortlived).
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-$(curl -4 -fsS https://api.ipify.org)}"
EMAIL="${2:-}"
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.prod.yml"
CONF=certbot/conf

if [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  ID_ARGS=(--ip-address "$TARGET" --preferred-profile shortlived)
  echo ">> Сертификат для IP: $TARGET"
else
  ID_ARGS=(-d "$TARGET")
  echo ">> Сертификат для домена: $TARGET"
fi
if [[ -n "$EMAIL" ]]; then MAIL_ARGS=(--email "$EMAIL"); else MAIL_ARGS=(--register-unsafely-without-email); fi

mkdir -p certbot/www "$CONF"

# Остатки временного сертификата от старой версии скрипта
if [[ ! -f "$CONF/renewal/app.conf" ]]; then
  rm -rf "$CONF/live/app" "$CONF/archive/app" 2>/dev/null || sudo rm -rf "$CONF/live/app" "$CONF/archive/app"
fi

# 1. Приложение поднимаем, nginx останавливаем — порт 80 нужен certbot
$COMPOSE up -d --build backend frontend
$COMPOSE stop nginx >/dev/null 2>&1 || true
$COMPOSE rm -f nginx >/dev/null 2>&1 || true

if ss -Htln 'sport = :80' | grep -q .; then
  echo "!! Порт 80 занят другим процессом:"
  sudo ss -tlnp 'sport = :80' || true
  echo "!! Освободите его (например: sudo systemctl disable --now nginx apache2) и запустите снова."
  exit 1
fi

# 2. Получаем сертификат (уже действующий не перевыпускается)
if ! $COMPOSE run --rm -p 80:80 --entrypoint certbot certbot certonly \
      --standalone \
      --cert-name app \
      "${ID_ARGS[@]}" "${MAIL_ARGS[@]}" \
      --agree-tos --non-interactive --keep-until-expiring; then
  echo
  echo "!! Сертификат не получен."
  echo "!! 'Connection refused' или 'Timeout' = порт 80 закрыт снаружи:"
  echo "!!   sudo ufw allow 80 && sudo ufw allow 443"
  echo "!!   и откройте 80/443 в файрволе (группах безопасности) в панели хостера."
  echo "!! После исправления просто запустите скрипт ещё раз."
  exit 1
fi

# 3. Запускаем nginx с HTTPS и контейнер автопродления
$COMPOSE up -d nginx certbot
sleep 2
code=$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1/api/health || true)
if [[ "$code" == "200" ]]; then
  echo ">> Готово: https://$TARGET"
else
  echo "!! HTTPS ответил кодом '$code'. Логи nginx:"
  $COMPOSE logs --tail=30 nginx
  exit 1
fi
