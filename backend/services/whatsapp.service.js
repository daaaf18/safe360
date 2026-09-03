const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcodeTerminal = require('qrcode-terminal');
const qrcode = require('qrcode');
const fs = require('fs');
const path = require('path');

let client = null;
let isReady = false;
let ultimoQR = null;

let watchdog = null;

// Cuánto esperamos, desde que arranca `initialize()`, a que llegue 'ready'
// antes de dar por muerto el intento y forzar uno nuevo. Confirmado que se
// puede quedar atorado (Chrome cargando, sin QR, sin error, sin evento
// alguno) indefinidamente — sin esto, nada lo saca de ese estado más que
// reiniciar el servidor a mano.
const TIMEOUT_CONEXION_MS = 90_000;

// Confirmado en vivo: si Chrome se mata a la fuerza (o `.destroy()` no
// alcanza a limpiar completo antes del siguiente intento), puede quedar
// este archivo de candado del perfil — y aunque ya no hay ningún proceso
// usándolo, `initialize()` truena con "The browser is already running"
// una y otra vez, solo porque el archivo sigue ahí (nos dejó en un bucle
// de reintentos infinito hasta que lo borré a mano). Borrarlo antes de
// cada intento es inofensivo si SÍ hay un Chrome vivo usándolo (lo vuelve
// a crear solo), y evita el bucle cuando no lo hay.
const LOCKFILE_PATH = path.join(__dirname, '..', '.wwebjs_auth', 'session', 'lockfile');
const limpiarLockfileHuerfano = () => {
  try {
    fs.unlinkSync(LOCKFILE_PATH);
  } catch (_) {
    // No existía, o sigue en uso por un Chrome que de verdad sigue vivo —
    // cualquiera de los dos es un estado normal, no hay nada que hacer.
  }
};

const iniciarWhatsApp = () => {
  if (watchdog) clearTimeout(watchdog);
  limpiarLockfileHuerfano();

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

  // ── Diagnóstico: para ver EXACTAMENTE en qué paso se atora (antes no
  // había forma de distinguir "todavía cargando" de "colgado de verdad",
  // porque no se registraba nada entre el QR y el 'ready') ──
  client.on('loading_screen', (percent, mensaje) => {
    console.log(`📲 WhatsApp cargando: ${percent}% — ${mensaje}`);
  });
  client.on('authenticated', () => {
    console.log('🔑 WhatsApp autenticado, esperando sincronizar...');
  });
  client.on('change_state', (estado) => {
    console.log('🔄 WhatsApp cambió de estado:', estado);
  });

  client.on('qr', async (qr) => {
    ultimoQR = qr;
    console.log('\n📱 Escanea este QR con WhatsApp para conectar Safe360:\n');
    qrcodeTerminal.generate(qr, { small: true });
  });

  client.on('ready', () => {
    isReady = true;
    ultimoQR = null;
    if (watchdog) clearTimeout(watchdog);
    console.log('✅ WhatsApp conectado correctamente');
  });

  client.on('disconnected', () => {
    isReady = false;
    console.log('❌ WhatsApp desconectado — reintentando en 8s...');
    // Antes esto no hacía nada más: una vez desconectado (sesión
    // invalidada, conflicto con otro dispositivo, etc.) el cliente se
    // quedaba "muerto" para siempre — sin QR nuevo, sin reconectar — hasta
    // reiniciar el servidor a mano. `client` (el de este cierre) queda con
    // el navegador ya cerrado tras logout/disconnected, así que no sirve
    // llamar `.initialize()` sobre el mismo objeto — hay que recrear todo
    // desde cero llamando `iniciarWhatsApp()` otra vez.
    if (watchdog) clearTimeout(watchdog);
    setTimeout(() => iniciarWhatsApp(), 8_000);
  });

  client.on('auth_failure', (mensaje) => {
    isReady = false;
    console.log('❌ WhatsApp falló autenticación:', mensaje, '— reintentando en 8s...');
    if (watchdog) clearTimeout(watchdog);
    setTimeout(() => iniciarWhatsApp(), 8_000);
  });

  client.initialize().catch((error) => {
    console.error('❌ Error inicializando WhatsApp:', error.message, '— reintentando en 8s...');
    if (watchdog) clearTimeout(watchdog);
    setTimeout(() => iniciarWhatsApp(), 8_000);
  });

  watchdog = setTimeout(() => {
    console.log(`⏱️  WhatsApp no llegó a 'ready' en ${TIMEOUT_CONEXION_MS / 1000}s — forzando reintento...`);
    const clienteAtorado = client;
    client = null;
    isReady = false;
    // .destroy() cierra el Chrome de Puppeteer de este intento antes de
    // lanzar uno nuevo — si no, se van acumulando procesos de Chrome
    // huérfanos con cada reintento (ya nos pasó).
    Promise.resolve(clienteAtorado?.destroy?.()).catch(() => {}).finally(() => {
      iniciarWhatsApp();
    });
  }, TIMEOUT_CONEXION_MS);
};

// Confirmado en vivo: el cliente puede quedar en un estado roto (la
// página de WhatsApp Web se refrescó/navegó sola por dentro, Puppeteer
// perdió la referencia al frame) SIN que dispare 'disconnected' — isReady
// se queda en `true` para siempre y CADA envío después de ese momento
// falla igual, hasta reiniciar el servidor a mano. Detectar el patrón del
// error y forzar una reconexión aquí mismo es lo que evita que un solo
// fallo se vuelva permanente.
let reconectando = false;

const forzarReconexion = (razon) => {
  if (reconectando) return; // ya hay una reconexión en curso, no lanzar dos
  reconectando = true;
  isReady = false;
  console.log(`🔄 Forzando reconexión de WhatsApp (${razon})...`);
  if (watchdog) clearTimeout(watchdog);
  const clienteRoto = client;
  client = null;
  Promise.resolve(clienteRoto?.destroy?.()).catch(() => {}).finally(() => {
    reconectando = false;
    iniciarWhatsApp();
  });
};

const enviarMensaje = async (telefono, mensaje) => {
  if (!isReady || !client) {
    console.log('WhatsApp no está listo, no se pudo enviar el mensaje');
    return false;
  }

  try {
    const numero = telefono.replace(/\D/g, '');

    // Antes esto adivinaba el chatId a mano (52 + número) y fallaba con
    // "no está en WhatsApp" para números mexicanos de celular reales —
    // WhatsApp históricamente espera "521" (52 + 1 + 10 dígitos) para
    // celulares de México, no "52" a secas, aunque el E.164 real ya no
    // lleve ese "1". `getNumberId` le pregunta directo a los servidores de
    // WhatsApp cuál es el id correcto para ese número (probando el
    // formato real), en vez de que nosotros adivinemos el prefijo.
    const numeroConLada = numero.startsWith('52') ? numero : `52${numero}`;
    const numeroInfo = await client.getNumberId(numeroConLada);

    if (!numeroInfo) {
      console.log(`WhatsApp: ${telefono} no tiene cuenta de WhatsApp registrada`);
      return false;
    }

    await client.sendMessage(numeroInfo._serialized, mensaje);
    console.log(`✅ Mensaje enviado a ${numeroInfo._serialized}`);
    return true;
  } catch (error) {
    console.error('Error enviando WhatsApp:', error.message);
    if (/frame|execution context|target closed|session closed/i.test(error.message)) {
      forzarReconexion('envío falló con la página en mal estado');
    }
    return false;
  }
};

const estaListo = () => isReady;

const getQRImage = async () => {
  if (!ultimoQR) return null;
  return await qrcode.toDataURL(ultimoQR);
};

module.exports = { iniciarWhatsApp, enviarMensaje, estaListo, getQRImage };