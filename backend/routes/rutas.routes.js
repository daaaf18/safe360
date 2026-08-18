const express = require('express');
const router = express.Router();
const { calcularRutaSegura } = require('../controllers/rutas.controller');
const { verificarToken } = require('../middleware/auth.middleware');

// POST /rutas/segura
router.post('/segura', verificarToken, calcularRutaSegura);

module.exports = router;