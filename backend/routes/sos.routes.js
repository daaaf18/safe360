const express = require('express');
const router = express.Router();
const { activarSOS, actualizarUbicacionSOS } = require('../controllers/sos.controller');
const { verificarToken } = require('../middleware/auth.middleware');
const { validarSOS, manejarErrores } = require('../middleware/validacion.middleware');

// POST /sos — Activar alerta de emergencia
router.post('/', verificarToken, validarSOS, manejarErrores, activarSOS);

// PUT /sos/ubicacion — Actualización periódica mientras la alerta sigue activa
router.put('/ubicacion', verificarToken, validarSOS, manejarErrores, actualizarUbicacionSOS);

module.exports = router;