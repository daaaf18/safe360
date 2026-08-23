const express = require('express');
const router = express.Router();
const { chat } = require('../controllers/chaty.controller');
const { verificarToken } = require('../middleware/auth.middleware');

// POST /chaty
router.post('/', verificarToken, chat);

module.exports = router;