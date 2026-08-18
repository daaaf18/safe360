const express = require('express');
const router = express.Router();
const { getScoreTemporal, getZonas } = require('../controllers/zonas.controller');
const { verificarToken } = require('../middleware/auth.middleware');

// GET /zonas — Listar zonas de riesgo
router.get('/', verificarToken, getZonas);

// GET /zonas/:id/score?hora=HH:MM — Score de seguridad temporal
router.get('/:id/score', verificarToken, getScoreTemporal);

module.exports = router;