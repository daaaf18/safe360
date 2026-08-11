const express = require('express');
const router = express.Router();
const luminariasController = require('../controllers/luminarias.controller');
const { verificarToken } = require('../middleware/auth.middleware');

// GET /luminarias — Listar luminarias cercanas a un punto
router.get('/', verificarToken, luminariasController.getLuminarias);

// PUT /luminarias/:id/estado — Actualizar estado de una luminaria
router.put('/:id/estado', verificarToken, luminariasController.actualizarEstado);

module.exports = router;