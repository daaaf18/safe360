const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');

let client = null;
let isReady = false;

const iniciarWhatsApp = () => {
  client = new Client({
    authStrategy: new LocalAuth(),
    puppeteer: {
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    },
  });

  client.on('qr', (qr) => {
    console.log('\n📱 Escanea este QR con WhatsApp para conectar Safe360:\n');
    qrcode.generate(qr, { small: true });
  });

  client.on('ready', () => {
    isReady = true;
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
    // Formato: 52XXXXXXXXXX@c.us (México = 52)
    const numero = telefono.replace(/\D/g, ''); // quitar caracteres no numéricos
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

module.exports = { iniciarWhatsApp, enviarMensaje, estaListo };