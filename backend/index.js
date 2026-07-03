const express = require('express');
const cors = require('cors');
require('dotenv').config();

const authRoutes = require('./routes/auth.routes');
const usersRoutes = require('./routes/users.routes');
const reportesRoutes = require('./routes/reportes.routes');
const luminariasRoutes = require('./routes/luminarias.routes');

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

// Ruta de prueba
app.get('/', (req, res) => {
  res.json({ message: 'Safe360 API funcionando correctamente' });
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Servidor corriendo en http://localhost:${PORT}`);
});