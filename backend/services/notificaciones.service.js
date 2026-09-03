const pool = require('../models/db');
const { enviarMensaje, estaListo } = require('./whatsapp.service');

// Detectar usuarios con rutas activas afectadas por un nuevo reporte y
// avisarles — por WhatsApp a sus contactos de confianza (como ya hacía) Y
// como alerta dentro de la app (Chaty la muestra al usuario mismo, ver
// GET /rutas/alertas). Esto último no depende de que WhatsApp esté
// conectado, así que se separó del chequeo estaListo() que antes hacía
// que TODO el aviso se saltara si WhatsApp no estaba listo.
const notificarRutasAfectadas = async (reporte) => {
  try {
    // Buscar rutas activas que pasen cerca del reporte (radio 300m)
    const rutasAfectadas = await pool.query(
      `SELECT ra.usuario_id, u.nombre,
       c.telefono, c.nombre as contacto_nombre
       FROM rutas_activas ra
       JOIN usuarios u ON ra.usuario_id = u.id
       LEFT JOIN contactos_confianza c ON c.usuario_id = ra.usuario_id
       WHERE ra.activa = TRUE
       AND ST_DWithin(
         ST_MakeLine(ra.origen, ra.destino)::geography,
         ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
         300
       )`,
      [reporte.longitud, reporte.latitud]
    );

    if (rutasAfectadas.rows.length === 0) return;

    // Agrupar por usuario para no duplicar la alerta ni el WhatsApp
    const usuariosNotificados = new Set();

    for (const fila of rutasAfectadas.rows) {
      if (usuariosNotificados.has(fila.usuario_id)) continue;
      usuariosNotificados.add(fila.usuario_id);

      // ── Alerta dentro de la app (Chaty) — para el usuario mismo ──
      const mensajeApp = `⚠️ Se reportó un incidente de *${reporte.categoria}* cerca de tu ruta activa. Mantente alerta.`;
      try {
        await pool.query(
          `INSERT INTO alertas_ruta (usuario_id, mensaje, categoria) VALUES ($1, $2, $3)`,
          [fila.usuario_id, mensajeApp, reporte.categoria]
        );
      } catch (error) {
        console.error('Error guardando alerta en app:', error.message);
      }

      // ── WhatsApp a su contacto de confianza (ya existía) ──
      if (fila.telefono && estaListo()) {
        const mensajeWhatsapp = `⚠️ *Alerta Safe360*\n\n` +
          `Nuevo reporte de *${reporte.categoria}* detectado cerca de la ruta activa de *${fila.nombre}*.\n\n` +
          `Mantente en contacto con ellos. Si no responden, considera verificar su situación.\n\n` +
          `_Safe360 — Navegación Urbana Segura_`;

        await enviarMensaje(fila.telefono, mensajeWhatsapp);
        console.log(`Notificación enviada al contacto de ${fila.nombre}`);
      }
    }

  } catch (error) {
    console.error('Error en notificarRutasAfectadas:', error.message);
  }
};

// Registrar una ruta como activa
const activarRuta = async (usuario_id, origen_lat, origen_lon, destino_lat, destino_lon) => {
  try {
    // Desactivar rutas previas del usuario
    await pool.query(
      'UPDATE rutas_activas SET activa = FALSE WHERE usuario_id = $1',
      [usuario_id]
    );

    // Registrar nueva ruta activa
    await pool.query(
      `INSERT INTO rutas_activas (usuario_id, origen, destino)
       VALUES ($1,
         ST_SetSRID(ST_MakePoint($2, $3), 4326),
         ST_SetSRID(ST_MakePoint($4, $5), 4326)
       )`,
      [usuario_id, origen_lon, origen_lat, destino_lon, destino_lat]
    );

    console.log(`Ruta activa registrada para usuario ${usuario_id}`);
  } catch (error) {
    console.error('Error en activarRuta:', error.message);
  }
};

// Desactivar ruta cuando el usuario llega
const desactivarRuta = async (usuario_id) => {
  try {
    await pool.query(
      'UPDATE rutas_activas SET activa = FALSE WHERE usuario_id = $1 AND activa = TRUE',
      [usuario_id]
    );
    console.log(`Ruta desactivada para usuario ${usuario_id}`);
  } catch (error) {
    console.error('Error en desactivarRuta:', error.message);
  }
};

module.exports = { notificarRutasAfectadas, activarRuta, desactivarRuta };
