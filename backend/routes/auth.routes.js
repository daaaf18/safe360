const express = require('express');
const router = express.Router();
const authController = require('../controllers/auth.controller');
const { validarRegistro, validarLogin, manejarErrores } = require('../middleware/validacion.middleware');

// POST /auth/register — Registrar un nuevo usuario
router.post('/register', validarRegistro, manejarErrores, authController.register);

// POST /auth/login — Iniciar sesión
router.post('/login', validarLogin, manejarErrores, authController.login);

module.exports = router;