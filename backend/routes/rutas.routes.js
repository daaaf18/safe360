const express = require('express');
const router = express.Router();
const { calcularRutaSegura } = require('../controllers/rutas.controller');
const { verificarToken } = require('../middleware/auth.middleware');
const { validarRuta, manejarErrores } = require('../middleware/validacion.middleware');

// POST /rutas/segura
router.post('/segura', verificarToken, validarRuta, manejarErrores, calcularRutaSegura);

module.exports = router;