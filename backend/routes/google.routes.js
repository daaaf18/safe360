const express = require('express');
const router = express.Router();
const { googleLogin } = require('../controllers/google.controller');

// POST /auth/google — Login con Google
router.post('/google', googleLogin);

module.exports = router;