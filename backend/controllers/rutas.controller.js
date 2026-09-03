const pool = require('../models/db');
const { activarRuta } = require('../services/notificaciones.service');
const { calcularScoreTemporal, calcularTrustScore } = require('../services/ml.service');

const MAPBOX_TOKEN = process.env.MAPBOX_API_KEY;

// Distancia en metros entre dos puntos lat/lon (fórmula haversine) — para
// filtrar resultados de Mapbox que de verdad caen dentro del radio pedido
// (a veces regresa el más cercano aunque esté más lejos, si no hay nada
// mejor cerca).
function distanciaHaversineM(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const rad = (g) => (g * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Puntos de interés seguros (farmacias, tiendas de conveniencia,
// gasolineras) a lo largo de la ruta — lugares con gente/cámaras/luz
// donde alguien puede pararse si se siente insegura caminando.
//
// Solo muestrea inicio/mitad/fin de la ruta (no cada punto) — una ruta
// caminando puede traer cientos de puntos de geometría, y esto ya hace
// hasta 9 llamadas a la API de Mapbox (3 categorías × 3 muestras) nada
// más por el simple hecho de calcular una ruta.
// IDs de categoría de la Search Box API de Mapbox (no la Geocoding API
// vieja — probado en vivo: mapbox.places con `types=poi` regresa 0
// resultados para estos términos, y sin ese filtro regresa direcciones o
// negocios de todo México sin relación real con `proximity`. La Search
// Box API sí hace búsqueda de POIs de verdad, cerca del punto pedido.
const CATEGORIAS_SEGURAS = [
  { tipo: 'farmacia', categoria: 'pharmacy' },
  { tipo: 'tienda_conveniencia', categoria: 'convenience_store' },
  { tipo: 'gasolinera', categoria: 'gas_station' },
];
const RADIO_PUNTOS_INTERES_M = 200;

async function buscarPuntosSeguros(puntosRuta) {
  if (!MAPBOX_TOKEN || !puntosRuta || puntosRuta.length === 0) return [];

  const indicesMuestra = [0, Math.floor(puntosRuta.length / 2), puntosRuta.length - 1];
  const muestras = [...new Set(indicesMuestra)].map(i => puntosRuta[i]);
  const encontrados = new Map(); // dedup por mapbox_id

  for (const punto of muestras) {
    for (const cat of CATEGORIAS_SEGURAS) {
      try {
        const url =
          `https://api.mapbox.com/search/searchbox/v1/category/${cat.categoria}` +
          `?proximity=${punto.lon},${punto.lat}&limit=5&language=es&access_token=${MAPBOX_TOKEN}`;
        const resp = await fetch(url, { signal: AbortSignal.timeout(6000) });
        if (!resp.ok) continue;
        const data = await resp.json();

        for (const feature of data.features || []) {
          const [lon, lat] = feature.geometry?.coordinates || [];
          if (lat == null || lon == null) continue;
          const dist = distanciaHaversineM(punto.lat, punto.lon, lat, lon);
          if (dist > RADIO_PUNTOS_INTERES_M) continue;

          const id = feature.properties?.mapbox_id || `${lat},${lon}`;
          if (!encontrados.has(id)) {
            encontrados.set(id, {
              id,
              nombre: feature.properties?.name || cat.tipo,
              tipo: cat.tipo,
              lat,
              lon,
              distancia_metros: Math.round(dist),
            });
          }
        }
      } catch (error) {
        console.error(`Error buscando puntos de interés (${cat.tipo}):`, error.message);
        // Uno fallando no debe tumbar el resto — se sigue con las demás
        // categorías/muestras, el usuario igual recibe su ruta.
      }
    }
  }

  return [...encontrados.values()];
}

/// Ruteo real por calles (a pie) usando la Directions API de Mapbox.
/// Devuelve `null` si no hay token, la petición falla, o Mapbox no
/// encuentra una ruta caminable entre los dos puntos — en cualquiera de
/// esos casos el llamador debe caer de vuelta a la línea recta
/// interpolada (ver calcularRutaSegura), no truena el endpoint completo.
// `usarAlternativa`: cuando el usuario toca "Ver ruta alternativa" en la
// app, se vuelve a pedir la ruta pero con alternatives=true y se regresa
// la opción [1] de Mapbox en vez de la [0] (la principal). Si Mapbox no
// tiene una segunda opción para ese origen/destino, cae de vuelta a la
// principal — no truena ni regresa vacío.
async function obtenerRutaCaminando(origenLat, origenLon, destinoLat, destinoLon, usarAlternativa = false) {
  if (!MAPBOX_TOKEN) {
    console.warn('MAPBOX_API_KEY no configurado — usando línea recta como fallback');
    return null;
  }

  const url =
    `https://api.mapbox.com/directions/v5/mapbox/walking/` +
    `${origenLon},${origenLat};${destinoLon},${destinoLat}` +
    `?geometries=geojson&overview=full` +
    `${usarAlternativa ? '&alternatives=true' : ''}` +
    `&access_token=${MAPBOX_TOKEN}`;

  try {
    const respuesta = await fetch(url);
    if (!respuesta.ok) {
      console.warn(`Mapbox Directions respondió ${respuesta.status} — usando línea recta`);
      return null;
    }

    const data = await respuesta.json();
    const rutas = data.routes || [];
    const indice = usarAlternativa && rutas.length > 1 ? 1 : 0;
    const ruta = rutas[indice];
    if (!ruta || !ruta.geometry || !ruta.geometry.coordinates) return null;

    return {
      // Mapbox regresa [lon, lat] por punto.
      puntos: ruta.geometry.coordinates.map(([lon, lat]) => ({ lat, lon })),
      geojson: ruta.geometry, // se usa tal cual para las consultas espaciales
      distanciaMetros: ruta.distance,
      hayAlternativa: rutas.length > 1,
    };
  } catch (error) {
    console.error('Error consultando Mapbox Directions:', error.message);
    return null;
  }
}

// POST /rutas/segura
const calcularRutaSegura = async (req, res) => {
  const { origen_lat, origen_lon, destino_lat, destino_lon, usar_alternativa } = req.body;
  const usuario_id = req.usuario.id;

  if (!origen_lat || !origen_lon || !destino_lat || !destino_lon) {
    return res.status(400).json({ error: 'Se requieren coordenadas de origen y destino' });
  }

  try {
    // 0. Ruta real por calles (a pie). Si Mapbox no responde o no hay
    // ruta caminable, seguimos con la línea recta de siempre — el
    // endpoint no debe fallar solo porque la API externa tuvo un problema.
    const rutaReal = await obtenerRutaCaminando(
      origen_lat, origen_lon, destino_lat, destino_lon, usar_alternativa === true
    );
    const esRutaReal = rutaReal !== null;

    // La geometría contra la que se comparan reportes/luminarias: la ruta
    // real caminando si Mapbox la dio, si no la línea recta de siempre.
    // Cada query abajo usa exactamente estos params (ni uno más) — Postgres
    // no puede inferir el tipo de un parámetro que se manda pero no
    // aparece en el texto de ESA query ("could not determine data type of
    // parameter $N"), así que no hay que reusar un array más grande con
    // placeholders que sobren.
    const paramsBase = [origen_lon, origen_lat, destino_lon, destino_lat];
    const geomRutaSQL = esRutaReal
      ? `ST_GeomFromGeoJSON($1)`
      : `ST_MakeLine(
           ST_SetSRID(ST_MakePoint($1, $2), 4326),
           ST_SetSRID(ST_MakePoint($3, $4), 4326)
         )`;
    const paramsGeomRuta = esRutaReal ? [JSON.stringify(rutaReal.geojson)] : paramsBase;

    // 1. Contar reportes verificados cerca de la ruta
    const reportesResult = await pool.query(
      `SELECT COUNT(*) as total,
       AVG(trust_score) as trust_promedio,
       COUNT(*) FILTER (WHERE categoria IN ('Robo', 'Acoso')) as reportes_graves
       FROM reportes
       WHERE estado = 'verificado'
       AND ST_DWithin(
         geom::geography,
         (${geomRutaSQL})::geography,
         500
       )`,
      paramsGeomRuta
    );

    // 2. Contar luminarias fundidas cerca de la ruta
    const luminariasResult = await pool.query(
      `SELECT COUNT(*) as fundidas
       FROM luminarias
       WHERE estado = 'fundida'
       AND ST_DWithin(
         geom::geography,
         (${geomRutaSQL})::geography,
         300
       )`,
      paramsGeomRuta
    );

    // 3. Distancia: la real de la ruta caminando si la tenemos, si no la
    // distancia en línea recta (que subestima bastante la caminata real).
    let distanciaMetros;
    if (esRutaReal) {
      distanciaMetros = rutaReal.distanciaMetros;
    } else {
      const distanciaResult = await pool.query(
        `SELECT ST_Distance(
           ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
           ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography
         ) as distancia_metros`,
        paramsBase
      );
      distanciaMetros = parseFloat(distanciaResult.rows[0].distancia_metros) || 0;
    }

    const reportes = reportesResult.rows[0];
    const luminarias = luminariasResult.rows[0];

    const totalReportes = parseInt(reportes.total) || 0;
    const reportesGraves = parseInt(reportes.reportes_graves) || 0;
    const luminariasFundidas = parseInt(luminarias.fundidas) || 0;

    // 4. Calcular TrustScore de la ruta (0-10) — misma función compartida
    // que usa zonas.controller.js (ver ml.service.js), para que el número
    // signifique siempre lo mismo en toda la app.
    const { trustScore, nivelRiesgo } = calcularTrustScore({
      reportesGraves, luminariasFundidas, totalReportes,
    });

    // 5. Geometría de la ruta para dibujar en el mapa: la real de Mapbox
    // si la tenemos, si no puntos cada 100m sobre la línea recta (mismo
    // fallback de siempre).
    let puntos;
    if (esRutaReal) {
      puntos = rutaReal.puntos;
    } else {
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
        paramsBase
      );
      puntos = geometriaResult.rows.map(r => ({
        lat: parseFloat(r.lat),
        lon: parseFloat(r.lon)
      }));
    }

    // 5b. Score temporal del trayecto — reusa el mismo K-Means de
    // zonas.controller.js (ver ml.service.js) pero con el historial de
    // reportes cerca de ESTA ruta en vez de una zona pre-dibujada de
    // `zonas_riesgo` (esa tabla casi no tiene zonas cargadas todavía, así
    // que depender de ella habría dejado esto sin datos casi siempre).
    let scoreTemporal = null;
    try {
      const historicoResult = await pool.query(
        `SELECT EXTRACT(HOUR FROM created_at) as hora,
         CASE WHEN categoria IN ('Robo', 'Acoso') THEN 1.0 ELSE 0.5 END as gravedad
         FROM reportes
         WHERE estado = 'verificado'
         AND ST_DWithin(geom::geography, (${geomRutaSQL})::geography, 500)`,
        paramsGeomRuta
      );
      const historico = historicoResult.rows.map(r => ({
        hora: parseInt(r.hora),
        gravedad: parseFloat(r.gravedad),
      }));
      const horaActual = new Date().getHours();
      const resultadoScore = calcularScoreTemporal(historico, horaActual);

      scoreTemporal = {
        hora_actual: horaActual,
        franja: resultadoScore.franja,
        score: resultadoScore.score,
        nivel_riesgo: resultadoScore.nivelRiesgo,
        metodo: resultadoScore.metodo,
        ml_info: resultadoScore.mlInfo,
        mensaje: resultadoScore.score < 7
          ? `Este tramo es más riesgoso en la ${resultadoScore.franja} — ` +
            `TrustScore ${resultadoScore.score}/10 basado en ${resultadoScore.totalHistorico} ` +
            `reporte(s) histórico(s)${resultadoScore.metodo === 'kmeans' ? ' (K-Means)' : ''}.`
          : null,
      };
    } catch (error) {
      console.error('Error calculando score temporal de la ruta:', error.message);
      // No tumba el cálculo de la ruta completa por esto — es información
      // extra, no el resultado principal.
    }

    // 5c. Puntos de interés seguros (farmacias, tiendas, gasolineras) a
    // lo largo del trayecto — solo si de verdad tenemos ruteo real por
    // calles; sobre la línea recta del fallback no tiene mucho sentido.
    const puntosInteres = esRutaReal ? await buscarPuntosSeguros(puntos) : [];

    // 6. Guardar la ruta en BD (historial)
    await pool.query(
      `INSERT INTO rutas (
         usuario_id, origen, destino, trust_score_promedio,
         distancia_metros, nivel_riesgo, puntos, ruteo_real
       )
       VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326),
               ST_SetSRID(ST_MakePoint($4, $5), 4326), $6,
               $7, $8, $9, $10)`,
      [
        usuario_id, origen_lon, origen_lat, destino_lon, destino_lat, trustScore,
        Math.round(distanciaMetros), nivelRiesgo, JSON.stringify(puntos), esRutaReal,
      ]
    );

    // 6b. Registrarla como ruta ACTIVA — esto es lo que hace que
    // notificarRutasAfectadas() (ver reportes.controller.js) te avise si
    // alguien reporta algo cerca de tu trayecto mientras vas caminando.
    // Antes esto solo pasaba en modo transporte; Ruta segura nunca la
    // registraba, así que el aviso nunca se disparaba desde aquí.
    await activarRuta(usuario_id, origen_lat, origen_lon, destino_lat, destino_lon);

    // Verificar si es una ruta frecuente del usuario
    const rutasFrecuentesResult = await pool.query(
      `SELECT COUNT(*) as total FROM rutas
       WHERE usuario_id = $1
       AND ST_DWithin(origen::geography, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, 200)
       AND ST_DWithin(destino::geography, ST_SetSRID(ST_MakePoint($4, $5), 4326)::geography, 200)`,
      [usuario_id, origen_lon, origen_lat, destino_lon, destino_lat]
    );

    const vecesUsada = parseInt(rutasFrecuentesResult.rows[0].total);
    const esRutaFrecuente = vecesUsada >= 3;

    res.json({
      origen: { lat: origen_lat, lon: origen_lon },
      destino: { lat: destino_lat, lon: destino_lon },
      puntos,
      ruteo_real: esRutaReal, // true = geometría real de Mapbox Directions, false = línea recta (fallback)
      hay_alternativa: esRutaReal ? (rutaReal.hayAlternativa ?? false) : false,
      distancia_metros: Math.round(distanciaMetros),
      trust_score_promedio: trustScore,
      nivel_riesgo: nivelRiesgo,
      reportes_en_zona: totalReportes,
      reportes_graves: reportesGraves,
      luminarias_fundidas: luminariasFundidas,
      mensaje: trustScore >= 7
        ? 'Ruta segura. Bajo nivel de incidentes reportados.'
        : trustScore >= 4
          ? 'Precaución. Hay incidentes reportados en esta zona.'
          : 'Alto riesgo. Se recomienda una ruta alternativa.',
      ruta_frecuente: esRutaFrecuente,
      veces_usada: vecesUsada,
      mensaje_frecuente: esRutaFrecuente
        ? `Usas esta ruta frecuentemente (${vecesUsada} veces). Chaty monitoreará el riesgo en tiempo real.`
        : null,
      score_temporal: scoreTemporal,
      puntos_interes: puntosInteres,
    });

  } catch (error) {
    console.error('Error en calcularRutaSegura:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

// GET /rutas/alertas — Alertas pendientes de "reporte cerca de tu ruta
// activa" para el usuario logueado (ver notificarRutasAfectadas en
// notificaciones.service.js). Chaty las poll-ea periódicamente y las
// muestra como mensaje suyo. Se marcan como leídas al regresarlas, para
// no repetir la misma alerta en el siguiente poll.
const getAlertas = async (req, res) => {
  const usuario_id = req.usuario.id;

  try {
    const resultado = await pool.query(
      `SELECT id, mensaje, categoria, created_at
       FROM alertas_ruta
       WHERE usuario_id = $1 AND leida = FALSE
       ORDER BY created_at ASC`,
      [usuario_id]
    );

    if (resultado.rows.length > 0) {
      const ids = resultado.rows.map(r => r.id);
      await pool.query(
        `UPDATE alertas_ruta SET leida = TRUE WHERE id = ANY($1::int[])`,
        [ids]
      );
    }

    res.json({ alertas: resultado.rows });
  } catch (error) {
    console.error('Error en getAlertas:', error.message);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
};

module.exports = { calcularRutaSegura, getAlertas };
