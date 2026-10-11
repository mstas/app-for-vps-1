#!/usr/bin/env bash
# Первичное получение HTTPS-сертификата Let's Encrypt.
#
#   bash scripts/init-https.sh                 # по IP сервера (определится сам)
#   bash scripts/init-https.sh 203.0.113.10    # по указанному IP
#   bash scripts/init-https.sh demo.example.com you@mail.com   # по домену
#
# Для IP выдаётся сертификат на 6 дней (профиль shortlived) — продлевается
# автоматически контейнером certbot из docker-compose.prod.yml.
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

if [[ -n "$EMAIL" ]]; then
  MAIL_ARGS=(--email "$EMAIL")
else
  MAIL_ARGS=(--register-unsafely-without-email)
fi

mkdir -p certbot/www "$CONF/live/app"

# 1. Временный самоподписанный сертификат, чтобы nginx смог стартовать на 443
if [[ ! -f "$CONF/renewal/app.conf" ]]; then
  echo ">> Временный сертификат для запуска nginx"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout "$CONF/live/app/privkey.pem" \
    -out "$CONF/live/app/fullchain.pem" \
    -subj "/CN=localhost" 2>/dev/null
fi

# 2. Поднимаем приложение с HTTPS-конфигом nginx
$COMPOSE up -d --build backend frontend nginx

# 3. Убираем временный сертификат и получаем настоящий через webroot
if [[ ! -f "$CONF/renewal/app.conf" ]]; then
  rm -rf "$CONF/live/app"
fi
$COMPOSE run --rm --entrypoint certbot certbot certonly \
  --webroot -w /var/www/certbot \
  --cert-name app \
  "${ID_ARGS[@]}" "${MAIL_ARGS[@]}" \
  --agree-tos --non-interactive --force-renewal

# 4. nginx перечитывает новый сертификат, запускаем автопродление
$COMPOSE exec nginx nginx -s reload
$COMPOSE up -d certbot

echo ">> Готово: https://$TARGET"
