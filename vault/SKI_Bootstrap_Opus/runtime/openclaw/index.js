const TelegramBot = require('node-telegram-bot-api');
const express = require('express');

const token = process.env.SKI_TELEGRAM_BOT_TOKEN;
const port = process.env.PORT || 3000;

// Express health endpoint
const app = express();
app.get('/', (req, res) => res.json({ status: 'ok', service: 'openclaw' }));
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'openclaw' }));

if (!token || token === 'your-token-here') {
  console.log('[OpenClaw] No Telegram token configured — running in gateway-only mode');
  app.listen(port, () => console.log(`[OpenClaw] Gateway listening on :${port}`));
} else {
  const bot = new TelegramBot(token, { polling: true });

  bot.onText(/\/start/, (msg) => {
    bot.sendMessage(msg.chat.id, 'SKI OpenClaw online. Sende /status fuer Systemstatus.');
  });

  bot.onText(/\/status/, (msg) => {
    const info = [
      'SKI System Status:',
      `Host: ${process.env.SKI_HOST_IP || 'unknown'}`,
      `LM Studio: ${process.env.SKI_LM_STUDIO_BASE_URL || 'unknown'}`,
      `Hermes Profile: ${process.env.SKI_HERMES_DEFAULT_PROFILE || 'unknown'}`,
    ].join('\n');
    bot.sendMessage(msg.chat.id, info);
  });

  bot.on('message', (msg) => {
    if (msg.text && !msg.text.startsWith('/')) {
      bot.sendMessage(msg.chat.id, `Empfangen: "${msg.text}" — Weiterleitung an Hermes kommt bald.`);
    }
  });

  app.listen(port, () => console.log(`[OpenClaw] Bot + Gateway on :${port}`));
}
