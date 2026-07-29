const pool = require('../models/db');
const { enviarMensaje, estaListo } = require('../services/whatsapp.service');

// POST /sos — Activar alerta de emergencia
const activarSOS = async (req, res) => {
  const { latitud, longitud } = req.body;
  const usuario_id = req.usuario.id;

  try {
    // Obtener datos del usuario
    const usuarioResult = await pool.query(
      'SELECT nombre FROM usuarios WHERE id = $1',
      [usuario_id]
    );

    if (usuarioResult.rows.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    const nombreUsuario = usuarioResult.rows[0].nombre;

    // Obtener contactos de confianza
    const contactosResult = await pool.query(
      'SELECT nombre, telefono FROM contactos_confianza WHERE usuario_id = $1',
      [usuario_id]
    );

    const contactos = contactosResult.rows;

    if (contactos.length === 0) {
      return res.status(400).json({ 
        error: 'No tienes contactos de confianza configurados' 
      });
    }

    // Construir mensaje de emergencia
    const googleMapsLink = `https://maps.google.com/?q=${latitud},${longitud}`;
    const mensaje = `🚨 *ALERTA SOS - Safe360*\n\n` +
      `*${nombreUsuario}* ha activado una alerta de emergencia.\n\n` +
      `📍 *Ubicación actual:*\n${googleMapsLink}\n\n` +
      `Por favor contáctale inmediatamente o llama al 911 si no responde.\n\n` +
      `_Este mensaje fue enviado automáticamente por Safe360_`;

    // Enviar WhatsApp a todos los contactos
    const resultados = [];
    for (const contacto of contactos) {
      const enviado = await enviarMensaje(contacto.telefono, mensaje);
      resultados.push({
        contacto: contacto.nombre,
        telefono: contacto.telefono,
        enviado,
      });
    }

    const exitosos = resultados.filter(r => r.enviado).length;

    res.json({
      message: `Alerta enviada a ${exitosos} de ${contactos.length} contactos`,
      resultados,
      whatsappActivo: estaListo(),
    });

  } catch (error) {
    console.error('Error en activarSOS:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = { activarSOS };