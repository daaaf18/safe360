const pool = require('../models/db');

// POST /rutas/transporte — Activar modo transporte
const activarModoTransporte = async (req, res) => {
  const { origen_lat, origen_lon, destino_lat, destino_lon, tipo_transporte } = req.body;
  const usuario_id = req.usuario.id;

  if (!origen_lat || !origen_lon || !destino_lat || !destino_lon) {
    return res.status(400).json({ error: 'Se requieren coordenadas de origen y destino' });
  }

  try {
    // Guardar ruta activa de transporte
        // Desactivar viaje anterior si existe
    await pool.query(
      'UPDATE rutas_activas SET activa = false WHERE usuario_id = $1',
      [usuario_id]
    );

    // Guardar nueva ruta activa de transporte
    await pool.query(
      `INSERT INTO rutas_activas (usuario_id, origen, destino, activa)
       VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326),
               ST_SetSRID(ST_MakePoint($4, $5), 4326), true)`,
      [usuario_id, origen_lon, origen_lat, destino_lon, destino_lat]
    );

    res.json({
      message: `Modo transporte activado — ${tipo_transporte || 'vehículo'}. Monitoreando tu trayecto.`,
      tipo_transporte: tipo_transporte || 'desconocido',
      recomendaciones: [
        'Verifica la placa y modelo del vehículo antes de subir',
        'Comparte tu viaje con un contacto de confianza',
        'Activa el SOS si el conductor se desvía de la ruta',
      ],
      numerosEmergencia: {
        emergencias: '911',
        lineaMujer: '800-911-2000',
        denuncia: '089',
      }
    });

  } catch (error) {
    console.error('Error en activarModoTransporte:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// POST /rutas/transporte/verificar — Verificar si hay desvío
const verificarDesvio = async (req, res) => {
  const { latitud_actual, longitud_actual } = req.body;
  const usuario_id = req.usuario.id;

  try {
    const rutaResult = await pool.query(
      `SELECT 
        ST_Distance(
          destino::geography,
          ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography
        ) as distancia_destino,
        ST_Distance(
          ST_MakeLine(origen, destino)::geography,
          ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography
        ) as desvio_metros
       FROM rutas_activas
       WHERE usuario_id = $3 AND activa = true`,
      [longitud_actual, latitud_actual, usuario_id]
    );

    if (rutaResult.rows.length === 0) {
      return res.status(404).json({ error: 'No tienes un viaje activo' });
    }

    const { distancia_destino, desvio_metros } = rutaResult.rows[0];
    const desvio = parseFloat(desvio_metros);
    const hayDesvio = desvio > 300; // más de 300 metros de la ruta esperada

    res.json({
      hayDesvio,
      desvio_metros: Math.round(desvio),
      distancia_destino_metros: Math.round(parseFloat(distancia_destino)),
      alerta: hayDesvio
        ? '⚠️ El vehículo se ha desviado más de 300 metros de la ruta esperada. ¿Estás bien?'
        : null,
    });

  } catch (error) {
    console.error('Error en verificarDesvio:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// POST /rutas/transporte/finalizar — Finalizar viaje
const finalizarViaje = async (req, res) => {
  const usuario_id = req.usuario.id;

  try {
    await pool.query(
      'UPDATE rutas_activas SET activa = false WHERE usuario_id = $1',
      [usuario_id]
    );

    res.json({ message: '✅ Viaje finalizado. ¡Llegaste segura!' });
  } catch (error) {
    console.error('Error en finalizarViaje:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = { activarModoTransporte, verificarDesvio, finalizarViaje };
