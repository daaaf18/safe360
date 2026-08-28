const express = require('express');
const router = express.Router();
const reportesController = require('../controllers/reportes.controller');
const { verificarToken } = require('../middleware/auth.middleware');
const { validarReporte, manejarErrores } = require('../middleware/validacion.middleware');

// POST /reportes — Crear un reporte
router.post('/', verificarToken, validarReporte, manejarErrores, reportesController.crearReporte);

// GET /reportes — Listar reportes (filtrado por zona o categoría)
router.get('/', verificarToken, reportesController.getReportes);

// GET /reportes/:id — Ver un reporte específico
router.get('/:id', verificarToken, reportesController.getReporte);

// PUT /reportes/:id — Actualizar estado de un reporte
router.put('/:id', verificarToken, reportesController.actualizarEstado);

module.exports = router;