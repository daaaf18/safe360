const express = require('express');
const router = express.Router();
const usersController = require('../controllers/users.controller');
const { getStats } = require('../controllers/stats.controller');
const { verificarToken } = require('../middleware/auth.middleware');
const { validarContacto, manejarErrores } = require('../middleware/validacion.middleware');

// GET /users/:id — Ver perfil de usuario
router.get('/:id', verificarToken, usersController.getPerfil);

// PUT /users/:id — Editar perfil de usuario
router.put('/:id', verificarToken, usersController.editarPerfil);

// PUT /users/:id/ubicacion — Actualizar ubicación en tiempo real
router.put('/:id/ubicacion', verificarToken, usersController.actualizarUbicacion);

// GET /users/:id/contactos — Ver contactos de confianza
router.get('/:id/contactos', verificarToken, usersController.getContactos);

// GET /users/:id/stats — Estadísticas y TrustScore personal
router.get('/:id/stats', verificarToken, getStats);

// GET /users/:id/rutas — Rutas frecuentes (últimas 3, con detección de uso repetido)
router.get('/:id/rutas', verificarToken, usersController.getRutas);

// POST /users/:id/contactos — Agregar contacto de confianza
router.post('/:id/contactos', verificarToken, validarContacto, manejarErrores, usersController.agregarContacto);

// PUT /users/:id/contactos/:contactoId — Editar contacto
router.put('/:id/contactos/:contactoId', verificarToken, validarContacto, manejarErrores, usersController.editarContacto);

// DELETE /users/:id/contactos/:contactoId — Eliminar contacto
router.delete('/:id/contactos/:contactoId', verificarToken, usersController.eliminarContacto);

module.exports = router;