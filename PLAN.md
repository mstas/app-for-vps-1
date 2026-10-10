# План: демо-приложение Spring Boot + Node.js + Nginx

Простое демо «Заметки»: бэкенд на Java Spring Boot отдаёт REST API, фронтенд на Node.js (Express) отдаёт страницу, Nginx стоит перед всем как единая точка входа. Всё запускается через Docker Compose — одинаково локально и на VPS.

## 1. Архитектура

```
Браузер ──► Nginx :80 (:443 на VPS)
              ├── /        ──► frontend (Node.js, Express) :3000
              └── /api/... ──► backend  (Spring Boot)       :8080
```

- Наружу открыт только Nginx. Backend и frontend доступны лишь внутри docker-сети.
- Фронтенд и API на одном домене → не нужен CORS.

## 2. Структура проекта

```
app-for-vps-1/
├── backend/                  # Spring Boot (Java 21, Maven)
│   ├── pom.xml
│   ├── Dockerfile
│   └── src/main/java/com/example/demo/
│       ├── DemoApplication.java
│       └── NoteController.java
├── frontend/                 # Node.js + Express
│   ├── package.json
│   ├── server.js
│   ├── public/index.html
│   └── Dockerfile
├── nginx/
│   └── default.conf
├── docker-compose.yml
└── .gitignore
```

## 3. Этапы работы

| # | Этап | Результат |
|---|------|-----------|
| 1 | Подготовить окружение | Установлены Git, Docker (+ для разработки без Docker: JDK 21, Node 22) |
| 2 | Backend | `GET/POST /api/notes`, `GET /api/health` работают на :8080 |
| 3 | Frontend | Страница на :3000 показывает и добавляет заметки через `/api` |
| 4 | Nginx | Конфиг проксирования `/` и `/api` |
| 5 | Docker | Dockerfile для backend и frontend, `docker-compose.yml` |
| 6 | Локальный запуск | http://localhost открывается, заметки добавляются |
| 7 | VPS | Сервер настроен, проект запущен, открыт по IP/домену |
| 8 | HTTPS (опционально) | Сертификат Let's Encrypt через certbot |

---

## 4. Backend (Spring Boot)

**Создать проект** — через https://start.spring.io: Maven, Java 21, Spring Boot 3.5.x, зависимости *Spring Web* и *Spring Boot Actuator*, group `com.example`, artifact `demo`. Распаковать в `backend/`.

Или из терминала:

```bash
curl https://start.spring.io/starter.zip \
  -d type=maven-project -d language=java -d javaVersion=21 \
  -d groupId=com.example -d artifactId=demo -d name=demo \
  -d dependencies=web,actuator -o backend.zip
unzip backend.zip -d backend && rm backend.zip
```

**`backend/src/main/java/com/example/demo/NoteController.java`** — хранение в памяти (для демо базы не нужно):

```java
package com.example.demo;

import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicLong;

@RestController
@RequestMapping("/api")
public class NoteController {

    public record Note(long id, String text) {}

    private final List<Note> notes = new CopyOnWriteArrayList<>();
    private final AtomicLong ids = new AtomicLong();

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }

    @GetMapping("/notes")
    public List<Note> list() {
        return notes;
    }

    @PostMapping("/notes")
    public Note add(@RequestBody Map<String, String> body) {
        Note n = new Note(ids.incrementAndGet(), body.getOrDefault("text", ""));
        notes.add(n);
        return n;
    }
}
```

**`backend/src/main/resources/application.properties`**:

```properties
server.port=8080
management.endpoints.web.exposure.include=health
```

**Проверка без Docker:**

```bash
cd backend
./mvnw spring-boot:run
curl http://localhost:8080/api/health        # {"status":"ok"}
```

**`backend/Dockerfile`** (многоэтапная сборка — на сервере не нужны ни JDK, ни Maven):

```dockerfile
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q dependency:go-offline
COPY src ./src
RUN mvn -q package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-Xmx256m", "-jar", "app.jar"]
```

> `-Xmx256m` ограничивает память — важно на дешёвом VPS с 1 ГБ RAM.

---

## 5. Frontend (Node.js + Express)

**`frontend/package.json`**:

```json
{
  "name": "frontend",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": { "express": "^4.21.2" }
}
```

**`frontend/server.js`**:

```js
const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.static(path.join(__dirname, "public")));
app.get("/healthz", (_req, res) => res.send("ok"));

app.listen(PORT, () => console.log(`Frontend on :${PORT}`));
```

**`frontend/public/index.html`**:

```html
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <title>Demo Notes</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 600px; margin: 40px auto; padding: 0 16px; }
    input { padding: 8px; width: 70%; } button { padding: 8px 16px; }
  </style>
</head>
<body>
  <h1>Заметки</h1>
  <p id="status">Проверка API…</p>
  <form id="form">
    <input id="text" placeholder="Новая заметка" required>
    <button>Добавить</button>
  </form>
  <ul id="list"></ul>

  <script>
    async function load() {
      const notes = await fetch("/api/notes").then(r => r.json());
      document.getElementById("list").innerHTML =
        notes.map(n => `<li>${n.id}. ${n.text.replace(/</g, "&lt;")}</li>`).join("");
    }
    fetch("/api/health").then(r => r.json())
      .then(d => status.textContent = "API: " + d.status)
      .catch(() => status.textContent = "API недоступен");

    document.getElementById("form").onsubmit = async e => {
      e.preventDefault();
      const input = document.getElementById("text");
      await fetch("/api/notes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: input.value })
      });
      input.value = "";
      load();
    };
    load();
  </script>
</body>
</html>
```

**`frontend/Dockerfile`**:

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "server.js"]
```

Добавить `frontend/.dockerignore` со строкой `node_modules`.

---

## 6. Nginx

**`nginx/default.conf`**:

```nginx
server {
    listen 80;
    server_name _;

    location /api/ {
        proxy_pass http://backend:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://frontend:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Имена `backend` и `frontend` — это имена сервисов из docker-compose, Docker сам резолвит их внутри сети.

---

## 7. Docker Compose

**`docker-compose.yml`**:

```yaml
services:
  backend:
    build: ./backend
    restart: unless-stopped
    expose:
      - "8080"

  frontend:
    build: ./frontend
    restart: unless-stopped
    expose:
      - "3000"

  nginx:
    image: nginx:1.27-alpine
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - backend
      - frontend
```

**`.gitignore`**:

```
backend/target/
frontend/node_modules/
.idea/
.DS_Store
```

---

## 8. Запуск локально (macOS)

1. Установить Docker Desktop (или OrbStack) и запустить его.
2. В корне проекта:

   ```bash
   docker compose up -d --build
   docker compose ps          # все три сервиса в статусе running
   ```
3. Открыть http://localhost — должна появиться страница «Заметки» и надпись «API: ok».
4. Полезные команды:

   ```bash
   docker compose logs -f backend     # логи бэкенда
   docker compose up -d --build backend   # пересобрать только бэкенд
   docker compose down                # остановить всё
   ```

**Режим разработки без Docker** (быстрее при частых правках): запустить backend через `./mvnw spring-boot:run`, frontend через `npm install && npm start`, а для `/api` на фронте временно настроить локальный nginx (`brew install nginx`) с тем же конфигом, но `proxy_pass http://localhost:8080` и `http://localhost:3000`. Либо просто держать nginx в Docker, а в конфиге указать `host.docker.internal`.

> Если порт 80 занят — поменять в compose на `"8081:80"` и открывать http://localhost:8081.

---

## 9. Развёртывание на VPS

Предполагается VPS с Ubuntu 24.04, минимум 1 ГБ RAM (лучше 2 ГБ — сборка Maven прожорлива), доступ по SSH.

### 9.1. Первичная настройка сервера

```bash
ssh root@<IP_СЕРВЕРА>

# обновления
apt update && apt upgrade -y

# отдельный пользователь вместо root
adduser deploy
usermod -aG sudo deploy
rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy   # перенос SSH-ключа

# файрвол: только SSH, HTTP, HTTPS
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw enable

# swap 2 ГБ — чтобы сборка Java не падала по памяти на маленьком VPS
fallocate -l 2G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### 9.2. Установка Docker

```bash
curl -fsSL https://get.docker.com | sh
usermod -aG docker deploy
# перелогиниться под deploy
ssh deploy@<IP_СЕРВЕРА>
docker --version && docker compose version
```

### 9.3. Доставка кода

Вариант A — через Git (рекомендуется):

```bash
# локально
git init && git add . && git commit -m "demo app"
git remote add origin git@github.com:<you>/app-for-vps-1.git
git push -u origin main

# на сервере
git clone https://github.com/<you>/app-for-vps-1.git
cd app-for-vps-1
```

Вариант B — без Git, копированием с Mac:

```bash
rsync -av --exclude node_modules --exclude target \
  ~/code/app-for-vps-1/ deploy@<IP_СЕРВЕРА>:~/app-for-vps-1/
```

### 9.4. Запуск

```bash
cd ~/app-for-vps-1
docker compose up -d --build
docker compose ps
curl http://localhost/api/health
```

Открыть в браузере `http://<IP_СЕРВЕРА>`. Благодаря `restart: unless-stopped` контейнеры поднимутся сами после перезагрузки сервера.

### 9.5. Обновление приложения

```bash
cd ~/app-for-vps-1
git pull
docker compose up -d --build
docker image prune -f      # убрать старые образы
```

### 9.6. Домен и HTTPS (опционально)

1. У регистратора домена создать A-запись `demo.example.com → <IP_СЕРВЕРА>`.
2. В `nginx/default.conf` заменить `server_name _;` на `server_name demo.example.com;`.
3. Самый простой путь — получить сертификат certbot'ом в standalone-режиме:

   ```bash
   docker compose stop nginx
   sudo apt install -y certbot
   sudo certbot certonly --standalone -d demo.example.com
   ```
4. Добавить в compose для nginx порт `"443:443"` и том `/etc/letsencrypt:/etc/letsencrypt:ro`, а в конфиг — HTTPS-сервер:

   ```nginx
   server {
       listen 80;
       server_name demo.example.com;
       return 301 https://$host$request_uri;
   }

   server {
       listen 443 ssl;
       server_name demo.example.com;
       ssl_certificate     /etc/letsencrypt/live/demo.example.com/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/demo.example.com/privkey.pem;

       location /api/ { proxy_pass http://backend:8080; proxy_set_header Host $host; proxy_set_header X-Forwarded-Proto https; }
       location /     { proxy_pass http://frontend:3000; proxy_set_header Host $host; }
   }
   ```
5. `docker compose up -d`. Продление: `sudo certbot renew` с хуками `--pre-hook "docker compose -f /home/deploy/app-for-vps-1/docker-compose.yml stop nginx" --post-hook "... start nginx"` — можно повесить в cron раз в месяц.

---

## 10. Чек-лист проверки

- [ ] `curl localhost:8080/api/health` (backend отдельно) → `{"status":"ok"}`
- [ ] `docker compose ps` — 3 контейнера `running`
- [ ] http://localhost — страница открывается, «API: ok», заметки добавляются
- [ ] На VPS: `http://<IP>` открывается снаружи, порты 8080/3000 снаружи **недоступны**
- [ ] После `sudo reboot` приложение поднимается само
- [ ] (если домен) https://demo.example.com с валидным сертификатом, http редиректит на https

## 11. Частые проблемы

| Симптом | Причина / решение |
|---|---|
| `502 Bad Gateway` от nginx | Backend ещё стартует (Spring ~10–20 с) или упал — смотреть `docker compose logs backend` |
| Сборка backend падает `Killed` на VPS | Не хватает памяти — добавить swap (п. 9.1) или собирать образ локально и пушить в Docker Hub/GHCR |
| На Mac собранный образ не стартует на VPS | Mac на Apple Silicon (arm64), VPS — amd64. Собирать на самом VPS, либо `docker buildx build --platform linux/amd64` |
| Сайт не открывается снаружи | Проверить `ufw status` и файрвол в панели хостера (порт 80/443) |
| Заметки пропали после перезапуска | Так и задумано — хранение в памяти. Следующий шаг — добавить PostgreSQL в compose и Spring Data JPA |

## 12. Что можно добавить потом

- PostgreSQL контейнер + Spring Data JPA вместо хранения в памяти
- GitHub Actions: сборка образов и деплой на VPS по `git push`
- Отдельный `docker-compose.prod.yml` с HTTPS-настройками
- Мониторинг: `/actuator/health` + Uptime Kuma
