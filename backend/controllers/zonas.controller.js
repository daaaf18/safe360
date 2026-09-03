const pool = require('../models/db');
const { calcularScoreTemporal, calcularTrustScore } = require('../services/ml.service');

// GET /zonas/:id/score?hora=HH:MM
// Calcula el nivel de riesgo de una zona para una hora específica.
//
// Si hay suficiente historial de reportes en la zona, usa K-Means sobre
// (hora del día, gravedad) para encontrar patrones horarios reales de
// riesgo en vez de la fórmula fija; si no, cae a la fórmula de siempre.
// Ver services/ml.service.js para la implementación de K-Means.
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
    // Historial completo de reportes verificados de la zona (hora +
    // gravedad de cada uno) — esto es lo que alimenta a K-Means. Antes
    // solo se guardaban conteos agregados para la fórmula fija.
    const historicoResult = await pool.query(
      `SELECT EXTRACT(HOUR FROM created_at) as hora,
              CASE WHEN categoria IN ('Robo', 'Acoso') THEN 1.0 ELSE 0.5 END as gravedad
       FROM reportes
       WHERE estado = 'verificado'
       AND ST_DWithin(
         geom::geography,
         (SELECT ST_Centroid(geom)::geography FROM zonas_riesgo WHERE id = $1),
         500
       )`,
      [id]
    );

    const historico = historicoResult.rows.map(r => ({
      hora: parseInt(r.hora),
      gravedad: parseFloat(r.gravedad),
    }));

    const { score, metodo, mlInfo, franja, nivelRiesgo } = calcularScoreTemporal(historico, horaNum);

    // Generar alerta de Chaty si el riesgo es mayor en esa hora
    let alertaChaty = null;
    if (score < 7) {
      alertaChaty = `Esta zona tiene riesgo ${nivelRiesgo} durante la ${franja} (${hora}). `;
      if (score < 4) {
        alertaChaty += '¿Deseas que busque una ruta alternativa más segura?';
      } else {
        alertaChaty += 'Mantente alerta y activa el seguimiento de ruta.';
      }
    }

    res.json({
      zona_id: parseInt(id),
      hora,
      franja,
      score_seguridad: score,
      nivel_riesgo: nivelRiesgo,
      metodo, // 'kmeans' o 'reglas_fijas' — cuál usó esta respuesta
      ml_info: mlInfo, // detalle del cluster si metodo === 'kmeans'
      alerta_chaty: alertaChaty,
    });

  } catch (error) {
    console.error('Error en getScoreTemporal:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// GET /zonas/aqui?lat=..&lon=..&hora=HH:MM — Qué tan segura está la zona
// alrededor de un punto (tu ubicación real) ahora mismo. A diferencia de
// GET /zonas/:id/score, no depende de que exista una zona pre-dibujada en
// `zonas_riesgo` (esa tabla casi no tiene datos todavía) — calcula
// directo sobre reportes/luminarias cerca de las coordenadas que mandes,
// igual que ya hace calcularRutaSegura para el trayecto de una ruta. Es
// lo que Chaty usa para "qué tan segura está mi zona".
const getZonaAqui = async (req, res) => {
  const { lat, lon, hora } = req.query;

  const latNum = parseFloat(lat);
  const lonNum = parseFloat(lon);
  if (isNaN(latNum) || isNaN(lonNum)) {
    return res.status(400).json({ error: 'Se requieren lat y lon numéricos' });
  }

  const horaNum = hora ? parseInt(hora.split(':')[0]) : new Date().getHours();
  if (isNaN(horaNum) || horaNum < 0 || horaNum > 23) {
    return res.status(400).json({ error: 'Hora inválida. Usa formato HH:MM (00-23)' });
  }

  try {
    const [reportesResult, historicoResult, luminariasResult] = await Promise.all([
      pool.query(
        `SELECT COUNT(*) as total,
         COUNT(*) FILTER (WHERE categoria IN ('Robo', 'Acoso')) as graves
         FROM reportes
         WHERE estado = 'verificado'
         AND ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, 500)`,
        [lonNum, latNum]
      ),
      pool.query(
        `SELECT EXTRACT(HOUR FROM created_at) as hora,
         CASE WHEN categoria IN ('Robo', 'Acoso') THEN 1.0 ELSE 0.5 END as gravedad
         FROM reportes
         WHERE estado = 'verificado'
         AND ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, 500)`,
        [lonNum, latNum]
      ),
      pool.query(
        `SELECT COUNT(*) as fundidas FROM luminarias
         WHERE estado = 'fundida'
         AND ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, 300)`,
        [lonNum, latNum]
      ),
    ]);

    const totalReportes = parseInt(reportesResult.rows[0].total) || 0;
    const reportesGraves = parseInt(reportesResult.rows[0].graves) || 0;
    const luminariasFundidas = parseInt(luminariasResult.rows[0].fundidas) || 0;

    // Mismo criterio que calcularRutaSegura (rutas.controller.js) — un
    // solo TrustScore con el mismo significado en toda la app, calculado
    // por la misma función compartida (ver ml.service.js).
    const { trustScore, nivelRiesgo: nivelRiesgoGeneral } = calcularTrustScore({
      reportesGraves, luminariasFundidas, totalReportes,
    });

    const historico = historicoResult.rows.map(r => ({
      hora: parseInt(r.hora),
      gravedad: parseFloat(r.gravedad),
    }));
    const temporal = calcularScoreTemporal(historico, horaNum);

    const mensaje = trustScore >= 7
      ? `Tu zona actual está tranquila — TrustScore ${trustScore}/10, con ${totalReportes} reporte(s) cerca.`
      : trustScore >= 4
        ? `Tu zona actual tiene riesgo medio — TrustScore ${trustScore}/10. Hay ${reportesGraves} reporte(s) grave(s) y ${luminariasFundidas} luminaria(s) fundida(s) cerca. Mantente alerta.`
        : `Tu zona actual tiene riesgo alto ahora mismo — TrustScore ${trustScore}/10, con ${reportesGraves} reporte(s) grave(s) cerca. Considera activar el modo escolta o pedirle a alguien que te acompañe.`;

    res.json({
      trust_score: trustScore,
      nivel_riesgo: nivelRiesgoGeneral,
      reportes_cerca: totalReportes,
      reportes_graves: reportesGraves,
      luminarias_fundidas: luminariasFundidas,
      score_temporal: {
        hora: horaNum,
        franja: temporal.franja,
        score: temporal.score,
        nivel_riesgo: temporal.nivelRiesgo,
        metodo: temporal.metodo,
      },
      mensaje,
    });
  } catch (error) {
    console.error('Error en getZonaAqui:', error.message);
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

module.exports = { getScoreTemporal, getZonas, getZonaAqui };
