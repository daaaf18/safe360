const express = require('express');
const router = express.Router();
const { calcularRutaSegura, getAlertas } = require('../controllers/rutas.controller');
const { verificarToken } = require('../middleware/auth.middleware');
const { validarRuta, manejarErrores } = require('../middleware/validacion.middleware');

// POST /rutas/segura
router.post('/segura', verificarToken, validarRuta, manejarErrores, calcularRutaSegura);

// GET /rutas/alertas — alertas pendientes de rutas afectadas (para Chaty)
router.get('/alertas', verificarToken, getAlertas);

module.exports = router;