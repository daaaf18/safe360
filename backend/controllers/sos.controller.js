const pool = require('../models/db');
const { enviarMensaje, estaListo } = require('../services/whatsapp.service');

// Números de emergencia oficiales México
const NUMEROS_EMERGENCIA = {
  emergencias:    '911',
  lineaMujer:     '800-911-2000',
  lineaPaz:       '800-290-0024',
  denuncia:       '089',
};

// Crear reporte automático si hay múltiples SOS en la misma zona
const verificarSOSMasivo = async (latitud, longitud) => {
  try {
    const resultado = await pool.query(
      `SELECT COUNT(*) as total FROM reportes
       WHERE categoria = 'SOS_Automatico'
       AND estado = 'verificado'
       AND created_at > NOW() - INTERVAL '30 minutes'
       AND ST_DWithin(
         geom::geography,
         ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
         300
       )`,
      [longitud, latitud]
    );

    const totalSOS = parseInt(resultado.rows[0].total);

    // Si hay 2 o más SOS previos (este sería el 3ro), crear reporte automático
    if (totalSOS >= 2) {
      await pool.query(
        `INSERT INTO reportes (usuario_id, categoria, descripcion, evidencia_url, geom, trust_score, estado)
         VALUES (1, 'SOS_Automatico',
           'Zona de alto riesgo detectada automáticamente por múltiples alertas SOS en la misma área.',
           null,
           ST_SetSRID(ST_MakePoint($1, $2), 4326),
           0.95,
           'verificado')`,
        [longitud, latitud]
      );
      console.log('⚠️ Reporte automático de zona creado por múltiples SOS');
      return true;
    }

    // Registrar este SOS para el conteo
    await pool.query(
      `INSERT INTO reportes (usuario_id, categoria, descripcion, evidencia_url, geom, trust_score, estado)
       VALUES (1, 'SOS_Automatico', 'SOS activado en esta zona.', null,
         ST_SetSRID(ST_MakePoint($1, $2), 4326), 0.5, 'verificado')`,
      [longitud, latitud]
    );

    return false;
  } catch (error) {
    console.error('Error en verificarSOSMasivo:', error.message);
    return false;
  }
};

// POST /sos — Activar alerta de emergencia
const activarSOS = async (req, res) => {
  const { latitud, longitud, silencioso = false } = req.body;
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

    // Verificar SOS masivo en background
    verificarSOSMasivo(latitud, longitud);

    const googleMapsLink = `https://maps.google.com/?q=${latitud},${longitud}`;

    const bloqueEmergencia = `\n\n📞 *Números de emergencia:*\n` +
      `• Emergencias: ${NUMEROS_EMERGENCIA.emergencias}\n` +
      `• Línea de la Mujer: ${NUMEROS_EMERGENCIA.lineaMujer}\n` +
      `• Denuncia anónima: ${NUMEROS_EMERGENCIA.denuncia}`;

    const mensaje = silencioso
      ? `🟡 *Modo Escolta — Safe360*\n\n` +
        `*${nombreUsuario}* ha activado el monitoreo silencioso.\n\n` +
        `📍 *Ubicación actual:*\n${googleMapsLink}\n\n` +
        `Está caminando y pidió que la monitorees discretamente. ` +
        `Si no recibes actualización en 30 minutos, contáctala.` +
        bloqueEmergencia +
        `\n\n_Safe360 — Modo Escolta Invisible_`
      : `🚨 *ALERTA SOS — Safe360*\n\n` +
        `*${nombreUsuario}* ha activado una alerta de emergencia.\n\n` +
        `📍 *Ubicación actual:*\n${googleMapsLink}\n\n` +
        `Por favor contáctale inmediatamente o llama al 911 si no responde.` +
        bloqueEmergencia +
        `\n\n_Este mensaje fue enviado automáticamente por Safe360_`;

    // Enviar WhatsApp a todos los contactos
    const resultados = [];
    if (estaListo()) {
      for (const contacto of contactos) {
        const enviado = await enviarMensaje(contacto.telefono, mensaje);
        resultados.push({
          contacto: contacto.nombre,
          telefono: contacto.telefono,
          enviado,
        });
      }
    }

    const exitosos = resultados.filter(r => r.enviado).length;

    res.json({
      message: silencioso
        ? `Modo escolta activado. ${exitosos} contacto(s) notificado(s) silenciosamente.`
        : `Alerta enviada a ${exitosos} de ${contactos.length} contactos`,
      silencioso,
      resultados,
      whatsappActivo: estaListo(),
      numerosEmergencia: NUMEROS_EMERGENCIA,
    });

  } catch (error) {
    console.error('Error en activarSOS:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = { activarSOS };