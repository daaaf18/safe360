const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcodeTerminal = require('qrcode-terminal');
const qrcode = require('qrcode');

let client = null;
let isReady = false;
let ultimoQR = null;

const iniciarWhatsApp = () => {
  client = new Client({
    authStrategy: new LocalAuth(),
    puppeteer: {
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--no-first-run',
        '--no-zygote',
        '--disable-gpu'
      ],
    },
  });

  client.on('qr', async (qr) => {
    ultimoQR = qr;
    console.log('\n📱 Escanea este QR con WhatsApp para conectar Safe360:\n');
    qrcodeTerminal.generate(qr, { small: true });
  });

  client.on('ready', () => {
    isReady = true;
    ultimoQR = null;
    console.log('✅ WhatsApp conectado correctamente');
  });

  client.on('disconnected', () => {
    isReady = false;
    console.log('❌ WhatsApp desconectado');
  });

  client.initialize();
};

const enviarMensaje = async (telefono, mensaje) => {
  if (!isReady || !client) {
    console.log('WhatsApp no está listo, no se pudo enviar el mensaje');
    return false;
  }

  try {
    const numero = telefono.replace(/\D/g, '');
    const chatId = numero.startsWith('52')
      ? `${numero}@c.us`
      : `52${numero}@c.us`;

    await client.sendMessage(chatId, mensaje);
    console.log(`✅ Mensaje enviado a ${chatId}`);
    return true;
  } catch (error) {
    console.error('Error enviando WhatsApp:', error.message);
    return false;
  }
};

const estaListo = () => isReady;

const getQRImage = async () => {
  if (!ultimoQR) return null;
  return await qrcode.toDataURL(ultimoQR);
};

module.exports = { iniciarWhatsApp, enviarMensaje, estaListo, getQRImage };