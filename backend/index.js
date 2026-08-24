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