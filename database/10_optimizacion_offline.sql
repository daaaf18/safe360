-- SEMANA 10: Snapshots offline y optimización

-- 1. Agregar índices geoespaciales GiST para acelerar consultas críticas en tu tabla real
CREATE INDEX IF NOT EXISTS idx_zonas_riesgo_geom_gist 
ON zonas_riesgo USING GIST (geom);

-- Índice normal para acelerar las búsquedas del historial
CREATE INDEX IF NOT EXISTS idx_historial_zona_id 
ON historial_incidentes (zona_id);

-- 2. Procedimiento para generar snapshot ligero y exportarlo para caché offline de Flutter
CREATE OR REPLACE FUNCTION generar_snapshot_offline()
RETURNS json AS $$
DECLARE
    resultado_geojson json;
BEGIN
    -- Construimos un GeoJSON (FeatureCollection) que Flutter puede leer nativamente
    SELECT json_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(json_agg(
            json_build_object(
                'type', 'Feature',
                'geometry', CAST(ST_AsGeoJSON(z.geom) AS json),
                'properties', json_build_object(
                    'zona_id', z.id,
                    'nivel_riesgo', z.nivel,
                    'ultima_actualizacion', z.ultima_actualizacion
                )
            )
        ), '[]'::json)
    )
    INTO resultado_geojson
    FROM zonas_riesgo z
    -- Filtramos para que solo descargue las zonas peligrosas (asumiendo que usas la palabra 'alto' o 'critico')
    WHERE z.nivel ILIKE '%alto%' OR z.nivel ILIKE '%critico%'; 

    RETURN resultado_geojson;
END;
$$ LANGUAGE plpgsql;