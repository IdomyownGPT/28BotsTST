# OpenClaw — Telegram Bot + Tool Gateway
FROM node:22-slim

WORKDIR /app

# Dependencies zuerst (Docker Cache nutzen)
COPY package*.json ./
RUN npm ci --production 2>/dev/null || npm install --production

# App-Code
COPY . .

EXPOSE 3000

CMD ["npm", "start"]
