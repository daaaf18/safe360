const express = require('express');
const router = express.Router();
const { activarModoTransporte, verificarDesvio, finalizarViaje } = require('../controllers/transporte.controller');
const { verificarToken } = require('../middleware/auth.middleware');

// POST /rutas/transporte — Activar modo transporte
router.post('/', verificarToken, activarModoTransporte);

// POST /rutas/transporte/verificar — Verificar desvío
router.post('/verificar', verificarToken, verificarDesvio);

// POST /rutas/transporte/finalizar — Finalizar viaje
router.post('/finalizar', verificarToken, finalizarViaje);

module.exports = router;
