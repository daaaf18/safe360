const express = require('express');
const cors = require('cors');
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

const app = express();

// Middlewares globales
app.use(cors());
app.use(express.json());
app.use('/uploads', express.static('uploads'));

// Rutas
app.use('/auth', authRoutes);
app.use('/users', usersRoutes);
app.use('/reportes', reportesRoutes);
app.use('/luminarias', luminariasRoutes);
app.use('/auth', googleRoutes);
app.use('/sos', sosRoutes);
app.use('/rutas', rutasRoutes);
app.use('/zonas', zonasRoutes);

// Ruta de prueba
app.get('/', (req, res) => {
  res.json({ message: 'Safe360 API funcionando correctamente' });
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Servidor corriendo en http://localhost:${PORT}`);
  iniciarWhatsApp();
});