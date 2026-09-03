const express = require('express');
const router = express.Router();
const { getScoreTemporal, getZonas, getZonaAqui } = require('../controllers/zonas.controller');
const { verificarToken } = require('../middleware/auth.middleware');

// GET /zonas — Listar zonas de riesgo
router.get('/', verificarToken, getZonas);

// GET /zonas/aqui?lat=..&lon=..&hora=HH:MM — Qué tan segura está la zona
// alrededor de un punto (para "qué tan segura está mi zona" en Chaty).
// Va ANTES de /:id/score para que "aqui" no se interprete como un :id.
router.get('/aqui', verificarToken, getZonaAqui);

// GET /zonas/:id/score?hora=HH:MM — Score de seguridad temporal
router.get('/:id/score', verificarToken, getScoreTemporal);

module.exports = router;