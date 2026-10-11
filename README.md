# Demo: Spring Boot + Node.js + Nginx

Приложение «Заметки»: REST API на Spring Boot, фронтенд на Node.js (Express), Nginx как точка входа.
Подробный план и инструкция по VPS — в [PLAN.md](PLAN.md).

## Быстрый старт (нужен Docker)

```bash
docker compose up -d --build
```

Открыть http://localhost. Если порт 80 занят: `HTTP_PORT=8081 docker compose up -d --build` → http://localhost:8081.

## API

| Метод | Путь | Описание |
|---|---|---|
| GET | `/api/health` | `{"status":"ok"}` |
| GET | `/api/notes` | список заметок |
| POST | `/api/notes` | тело `{"text":"..."}` → 201 |
| DELETE | `/api/notes/{id}` | удалить → 204 |

## Без Docker

```bash
# backend (нужны JDK 21 и Maven)
cd backend && mvn spring-boot:run

# frontend (нужен Node 22)
cd frontend && npm install && npm start
```

Для связки `/api` между ними нужен nginx — см. PLAN.md, раздел 8.

## Тесты backend

```bash
cd backend && mvn test
```

## HTTPS на VPS (без домена)

Let's Encrypt выдаёт сертификаты на IP-адрес (срок 6 дней, продлевается автоматически).
На сервере, в папке проекта:

```bash
bash scripts/init-https.sh            # IP определится сам
# или: bash scripts/init-https.sh 203.0.113.10
```

Дальше запуск/обновление всегда с прод-надстройкой:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Появится домен — тот же скрипт: `bash scripts/init-https.sh demo.example.com you@mail.com`.
