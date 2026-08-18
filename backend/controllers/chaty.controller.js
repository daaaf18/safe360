const { procesarMensaje } = require('../services/chaty.service');

// POST /chaty
const chat = async (req, res) => {
  const { mensaje } = req.body;

  if (!mensaje || mensaje.trim() === '') {
    return res.status(400).json({ error: 'El mensaje no puede estar vacío' });
  }

  const respuesta = await procesarMensaje(mensaje, { usuario_id: req.usuario.id });
  res.json(respuesta);
};

module.exports = { chat };