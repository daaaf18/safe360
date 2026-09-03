const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const { iniciarWhatsApp } = require('./services/whatsapp.service');
const authRoutes = require('./routes/auth.routes');
const usersRoutes = require('./routes/users.routes');
const reportesRoutes = require('./routes/reportes.routes');
const luminariasRoutes = require('./routes/luminarias.routes');
const googleRoutes = require('./routes/google.routes');
const sosRoutes = require('./routes/sos.routes');
const rutasRoutes = require('./routes/rutas.routes');
const zonasRoutes = require('./routes/zonas.routes');
const chatyRoutes = require('./routes/chaty.routes');
const transporteRoutes = require('./routes/transporte.routes');

// ── Red de seguridad global ───────────────────────────────
// whatsapp-web.js a veces truena con errores no capturados en su propia
// limpieza interna (ej. en Windows, "EBUSY: resource busy or locked" al
// intentar borrar un archivo temporal de Chromium todavía en uso) —
// sin esto, esa excepción tumbaba TODO el servidor: login, SOS, reportes,
// todo, no solo WhatsApp. Lo registramos y seguimos vivos.
process.on('uncaughtException', (err) => {
  console.error('⚠️  Excepción no capturada (el servidor sigue corriendo):', err.message);
});
process.on('unhandledRejection', (reason) => {
  console.error('⚠️  Promesa rechazada sin capturar (el servidor sigue corriendo):', reason);
});

const app = express();

// ── CORS restrictivo ──────────────────────────────────────
const corsOptions = {
  origin: [
    'http://localhost:3000',
    'http://10.0.2.2:3000',  // emulador Android
    process.env.FRONTEND_URL, // URL de producción cuando se haga deploy
  ].filter(Boolean),
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
};
app.use(cors(corsOptions));

// ── Rate limiting ─────────────────────────────────────────
const limiterGeneral = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: 100,                  // máx 100 requests por IP
  message: { error: 'Demasiadas solicitudes, intenta más tarde' },
});

const limiterAuth = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10, // más estricto para login/register
  message: { error: 'Demasiados intentos, intenta más tarde' },
});

const limiterSOS = rateLimit({
  windowMs: 60 * 1000, // 1 minuto
  max: 5,              // máx 5 SOS por minuto
  message: { error: 'Demasiadas alertas en poco tiempo' },
});

app.use(limiterGeneral);

// ── Log de peticiones (para diagnóstico — no había ninguno) ──
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.originalUrl} desde ${req.ip}`);
  next();
});

// ── Middlewares globales ──────────────────────────────────
app.use(express.json());
app.use('/uploads', express.static('uploads'));

// ── Rutas ─────────────────────────────────────────────────
app.use('/auth', limiterAuth, authRoutes);
app.use('/auth', limiterAuth, googleRoutes);
app.use('/users', usersRoutes);
app.use('/reportes', reportesRoutes);
app.use('/luminarias', luminariasRoutes);
app.use('/sos', limiterSOS, sosRoutes);
app.use('/rutas', rutasRoutes);
app.use('/zonas', zonasRoutes);
app.use('/chaty', chatyRoutes);
app.use('/rutas/transporte', transporteRoutes);

// ── Ruta QR WhatsApp ──────────────────────────────────────
app.get('/qr', async (req, res) => {
  const { getQRImage } = require('./services/whatsapp.service');
  const qrImage = await getQRImage();
  if (!qrImage) return res.json({ message: 'WhatsApp ya está conectado o QR no disponible' });
  res.send(`<html><body style="background:#000;display:flex;justify-content:center;align-items:center;height:100vh"><img src="${qrImage}" style="width:300px"/></body></html>`);
});

// Diagnóstico rápido: antes no había forma de saber desde afuera si
// WhatsApp de verdad ya terminó de reconectar tras un reinicio del server
// (el endpoint /qr solo dice "sin QR", que es ambiguo entre "ya conectado"
// y "todavía cargando").
app.get('/whatsapp/estado', (req, res) => {
  const { estaListo } = require('./services/whatsapp.service');
  res.json({ conectado: estaListo() });
});

// ── Ruta de prueba ────────────────────────────────────────
app.get('/', (req, res) => {
  res.json({ message: 'Safe360 API funcionando correctamente' });
});

// ── Manejo global de errores ──────────────────────────────
app.use((err, req, res, next) => {
  console.error('Error no controlado:', err.message);
  res.status(err.status || 500).json({
    error: err.message || 'Error interno del servidor',
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Servidor corriendo en http://localhost:${PORT}`);
  iniciarWhatsApp();
});