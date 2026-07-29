const express = require('express');
const router = express.Router();
const { activarSOS } = require('../controllers/sos.controller');
const { verificarToken } = require('../middleware/auth.middleware');

// POST /sos — Activar alerta de emergencia
router.post('/', verificarToken, activarSOS);

module.exports = router;