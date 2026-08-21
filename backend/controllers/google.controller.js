const { OAuth2Client } = require('google-auth-library');
const jwt = require('jsonwebtoken');
const pool = require('../models/db');
require('dotenv').config();

const client = new OAuth2Client(process.env.GOOGLE_WEB_CLIENT_ID);

const googleLogin = async (req, res) => {
  const { idToken } = req.body;

  try {
    // Verificar el token con Google
    const ticket = await client.verifyIdToken({
      idToken,
      audience: [
        process.env.GOOGLE_WEB_CLIENT_ID,
        process.env.GOOGLE_ANDROID_CLIENT_ID,
      ],
    });

    const payload = ticket.getPayload();
    const { email, name, sub: googleId } = payload;

    // Buscar si el usuario ya existe
    let resultado = await pool.query(
      'SELECT * FROM usuarios WHERE email = $1',
      [email]
    );

    let usuario;

    if (resultado.rows.length === 0) {
      // Crear usuario nuevo con Google
      const nuevo = await pool.query(
        `INSERT INTO usuarios (nombre, email, password_hash, google_id)
         VALUES ($1, $2, $3, $4)
         RETURNING id, nombre, email`,
        [name, email, 'GOOGLE_AUTH', googleId]
      );
      usuario = nuevo.rows[0];
    } else {
      usuario = resultado.rows[0];
    }

    // Generar JWT
    const token = jwt.sign(
      { id: usuario.id, email: usuario.email },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    res.json({
      usuario: { id: usuario.id, nombre: usuario.nombre, email: usuario.email },
      token,
    });

  } catch (error) {
    console.error('Error en Google Login:', error.message);
    res.status(401).json({ error: 'Token de Google inválido' });
  }
};

module.exports = { googleLogin };