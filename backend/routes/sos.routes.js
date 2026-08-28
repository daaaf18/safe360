const express = require('express');
const router = express.Router();
const { activarSOS } = require('../controllers/sos.controller');
const { verificarToken } = require('../middleware/auth.middleware');
const { validarSOS, manejarErrores } = require('../middleware/validacion.middleware');

// POST /sos — Activar alerta de emergencia
router.post('/', verificarToken, validarSOS, manejarErrores, activarSOS);

module.exports = router;