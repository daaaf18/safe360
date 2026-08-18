const pool = require('../models/db');

// GET /zonas/:id/score?hora=HH:MM
// Calcula el nivel de riesgo de una zona para una hora específica
const getScoreTemporal = async (req, res) => {
  const { id } = req.params;
  const { hora } = req.query;

  if (!hora) {
    return res.status(400).json({ error: 'Se requiere el parámetro hora (formato HH:MM)' });
  }

  const horaNum = parseInt(hora.split(':')[0]);
  if (isNaN(horaNum) || horaNum < 0 || horaNum > 23) {
    return res.status(400).json({ error: 'Hora inválida. Usa formato HH:MM (00-23)' });
  }

  try {
    // Buscar reportes históricos en esa zona por franja horaria
    const resultado = await pool.query(
      `SELECT 
        COUNT(*) as total_reportes,
        COUNT(*) FILTER (WHERE EXTRACT(HOUR FROM created_at) = $2) as reportes_esa_hora,
        COUNT(*) FILTER (WHERE EXTRACT(HOUR FROM created_at) BETWEEN $3 AND $4) as reportes_franja,
        AVG(trust_score) as trust_promedio,
        COUNT(*) FILTER (WHERE categoria IN ('Robo', 'Acoso') AND EXTRACT(HOUR FROM created_at) = $2) as reportes_graves_hora
       FROM reportes
       WHERE estado = 'verificado'
       AND ST_DWithin(
         geom::geography,
         (SELECT ST_Centroid(geom)::geography FROM zonas_riesgo WHERE id = $1),
         500
       )`,
      [id, horaNum, Math.max(0, horaNum - 1), Math.min(23, horaNum + 1)]
    );

    const datos = resultado.rows[0];
    const reportesEsaHora = parseInt(datos.reportes_esa_hora) || 0;
    const reportesGravesHora = parseInt(datos.reportes_graves_hora) || 0;
    const reportesFranja = parseInt(datos.reportes_franja) || 0;

    // Calcular score (0-10) para esa hora
    let score = 10.0;
    score -= Math.min(reportesEsaHora * 1.5, 5.0);
    score -= Math.min(reportesGravesHora * 2.0, 4.0);
    score -= Math.min(reportesFranja * 0.3, 2.0);
    score = Math.max(0.0, Math.round(score * 10) / 10);

    // Clasificar franja horaria
    let franjaDescripcion;
    if (horaNum >= 6 && horaNum < 12) franjaDescripcion = 'mañana';
    else if (horaNum >= 12 && horaNum < 18) franjaDescripcion = 'tarde';
    else if (horaNum >= 18 && horaNum < 22) franjaDescripcion = 'noche temprana';
    else franjaDescripcion = 'madrugada';

    const nivelRiesgo = score >= 7 ? 'bajo' : score >= 4 ? 'medio' : 'alto';

    // Generar alerta de Chaty si el riesgo es mayor en esa hora
    let alertaChaty = null;
    if (score < 7) {
      alertaChaty = `Esta zona tiene riesgo ${nivelRiesgo} durante la ${franjaDescripcion} (${hora}). `;
      if (score < 4) {
        alertaChaty += '¿Deseas que busque una ruta alternativa más segura?';
      } else {
        alertaChaty += 'Mantente alerta y activa el seguimiento de ruta.';
      }
    }

    res.json({
      zona_id: parseInt(id),
      hora,
      franja: franjaDescripcion,
      score_seguridad: score,
      nivel_riesgo: nivelRiesgo,
      reportes_en_esa_hora: reportesEsaHora,
      reportes_graves: reportesGravesHora,
      alerta_chaty: alertaChaty,
    });

  } catch (error) {
    console.error('Error en getScoreTemporal:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// GET /zonas — Listar todas las zonas de riesgo
const getZonas = async (req, res) => {
  try {
    const resultado = await pool.query(
      `SELECT id, nivel,
       ST_AsGeoJSON(geom) as geojson,
       ultima_actualizacion
       FROM zonas_riesgo
       ORDER BY ultima_actualizacion DESC
       LIMIT 50`
    );
    res.json(resultado.rows);
  } catch (error) {
    console.error('Error en getZonas:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = { getScoreTemporal, getZonas };