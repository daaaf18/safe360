const express = require('express');
const router = express.Router();
const usersController = require('../controllers/users.controller');
const { verificarToken } = require('../middleware/auth.middleware');

// GET /users/:id — Ver perfil de usuario
router.get('/:id', verificarToken, usersController.getPerfil);

// PUT /users/:id — Editar perfil de usuario
router.put('/:id', verificarToken, usersController.editarPerfil);

// PUT /users/:id/ubicacion — Actualizar ubicación en tiempo real
router.put('/:id/ubicacion', verificarToken, usersController.actualizarUbicacion);

// GET /users/:id/contactos — Ver contactos de confianza
router.get('/:id/contactos', verificarToken, usersController.getContactos);

// POST /users/:id/contactos — Agregar contacto de confianza
router.post('/:id/contactos', verificarToken, usersController.agregarContacto);

// PUT /users/:id/contactos/:contactoId — Editar contacto
router.put('/:id/contactos/:contactoId', verificarToken, usersController.editarContacto);

// DELETE /users/:id/contactos/:contactoId — Eliminar contacto
router.delete('/:id/contactos/:contactoId', verificarToken, usersController.eliminarContacto);

module.exports = router;