const pool = require('../models/db');

// POST /rutas/segura
const calcularRutaSegura = async (req, res) => {
  const { origen_lat, origen_lon, destino_lat, destino_lon } = req.body;
  const usuario_id = req.usuario.id;

  if (!origen_lat || !origen_lon || !destino_lat || !destino_lon) {
    return res.status(400).json({ error: 'Se requieren coordenadas de origen y destino' });
  }

  try {
    // 1. Contar reportes verificados en el área entre origen y destino
    const reportesResult = await pool.query(
      `SELECT COUNT(*) as total,
       AVG(trust_score) as trust_promedio,
       COUNT(*) FILTER (WHERE categoria IN ('Robo', 'Acoso')) as reportes_graves
       FROM reportes
       WHERE estado = 'verificado'
       AND ST_DWithin(
         geom::geography,
         ST_MakeLine(
           ST_SetSRID(ST_MakePoint($1, $2), 4326),
           ST_SetSRID(ST_MakePoint($3, $4), 4326)
         )::geography,
         500
       )`,
      [origen_lon, origen_lat, destino_lon, destino_lat]
    );

    // 2. Contar luminarias fundidas en el área
    const luminariasResult = await pool.query(
      `SELECT COUNT(*) as fundidas
       FROM luminarias
       WHERE estado = 'fundida'
       AND ST_DWithin(
         geom::geography,
         ST_MakeLine(
           ST_SetSRID(ST_MakePoint($1, $2), 4326),
           ST_SetSRID(ST_MakePoint($3, $4), 4326)
         )::geography,
         300
       )`,
      [origen_lon, origen_lat, destino_lon, destino_lat]
    );

    // 3. Calcular distancia entre origen y destino
    const distanciaResult = await pool.query(
      `SELECT ST_Distance(
         ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
         ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography
       ) as distancia_metros`,
      [origen_lon, origen_lat, destino_lon, destino_lat]
    );

    const reportes = reportesResult.rows[0];
    const luminarias = luminariasResult.rows[0];
    const distancia = distanciaResult.rows[0];

    const totalReportes = parseInt(reportes.total) || 0;
    const reportesGraves = parseInt(reportes.reportes_graves) || 0;
    const luminariasFoundidas = parseInt(luminarias.fundidas) || 0;
    const distanciaMetros = parseFloat(distancia.distancia_metros) || 0;

    // 4. Calcular TrustScore de la ruta (0-10)
    // Penalizar por reportes graves y luminarias fundidas
    let trustScore = 10.0;
    trustScore -= Math.min(reportesGraves * 1.5, 5.0);
    trustScore -= Math.min(luminariasFoundidas * 0.5, 3.0);
    trustScore -= Math.min(totalReportes * 0.3, 2.0);
    trustScore = Math.max(0.0, Math.round(trustScore * 10) / 10);

    const nivelRiesgo = trustScore >= 7 ? 'bajo' : trustScore >= 4 ? 'medio' : 'alto';

        // 5. Generar geometría de la ruta (puntos cada 100m)
    const geometriaResult = await pool.query(
      `SELECT ST_X(dp.geom) as lon, ST_Y(dp.geom) as lat
       FROM ST_DumpPoints(
         ST_Segmentize(
           ST_MakeLine(
             ST_SetSRID(ST_MakePoint($1, $2), 4326),
             ST_SetSRID(ST_MakePoint($3, $4), 4326)
           )::geography,
           100
         )::geometry
       ) AS dp(path, geom)`,
      [origen_lon, origen_lat, destino_lon, destino_lat]
    );

    const puntos = geometriaResult.rows.map(r => ({
      lat: parseFloat(r.lat),
      lon: parseFloat(r.lon)
    }));

    // 6. Guardar la ruta en BD
    await pool.query(
      `INSERT INTO rutas (usuario_id, origen, destino, trust_score_promedio)
       VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326),
               ST_SetSRID(ST_MakePoint($4, $5), 4326), $6)`,
      [usuario_id, origen_lon, origen_lat, destino_lon, destino_lat, trustScore]
    );

    res.json({
      origen: { lat: origen_lat, lon: origen_lon },
      destino: { lat: destino_lat, lon: destino_lon },
      puntos,
      distancia_metros: Math.round(distanciaMetros),
      trust_score_promedio: trustScore,
      nivel_riesgo: nivelRiesgo,
      reportes_en_zona: totalReportes,
      reportes_graves: reportesGraves,
      luminarias_fundidas: luminariasFoundidas,
      mensaje: trustScore >= 7
        ? 'Ruta segura. Bajo nivel de incidentes reportados.'
        : trustScore >= 4
          ? 'Precaución. Hay incidentes reportados en esta zona.'
          : 'Alto riesgo. Se recomienda una ruta alternativa.',
    });

  } catch (error) {
    console.error('Error en calcularRutaSegura:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = { calcularRutaSegura };