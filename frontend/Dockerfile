FROM node:22-alpine
WORKDIR /app
COPY --chown=node:node package*.json ./
RUN npm install --omit=dev
COPY --chown=node:node . .
ENV NODE_ENV=production
EXPOSE 3000
USER node
CMD ["node", "server.js"]
