const TelegramBot = require('node-telegram-bot-api');
const express = require('express');

const token = process.env.SKI_TELEGRAM_BOT_TOKEN_2;
const port = process.env.PORT || 3001;
const botName = process.env.SKI_BOT_NAME || 'OpenClaw-2';

// Express health endpoint
const app = express();
app.get('/', (req, res) => res.json({ status: 'ok', service: botName }));
app.get('/health', (req, res) => res.json({ status: 'ok', service: botName }));

if (!token || token === 'your-token-here') {
  console.log(`[${botName}] No Telegram token configured — running in gateway-only mode`);
  app.listen(port, () => console.log(`[${botName}] Gateway listening on :${port}`));
} else {
  const bot = new TelegramBot(token, { polling: true });

  bot.onText(/\/start/, (msg) => {
    bot.sendMessage(msg.chat.id, `${botName} online. Sende /status fuer Systemstatus.`);
  });

  bot.onText(/\/status/, (msg) => {
    const info = [
      `${botName} Status:`,
      `Host: ${process.env.SKI_HOST_IP || 'unknown'}`,
      `LM Studio: ${process.env.SKI_LM_STUDIO_BASE_URL || 'unknown'}`,
      `Hermes: http://ski-hermes-agent:9377`,
    ].join('\n');
    bot.sendMessage(msg.chat.id, info);
  });

  bot.on('message', (msg) => {
    if (msg.text && !msg.text.startsWith('/')) {
      bot.sendMessage(msg.chat.id, `[${botName}] Empfangen: "${msg.text}"`);
    }
  });

  app.listen(port, () => console.log(`[${botName}] Bot + Gateway on :${port}`));
}
