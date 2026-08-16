-- SEMANA 7: Algoritmo de Ruta Segura

-- 1. Aseguramos que la extensión de ruteo espacial esté habilitada
CREATE EXTENSION IF NOT EXISTS pgrouting;

-- 2. Función para evaluar el nivel de seguridad de un tramo de calle
-- Esta función busca reportes activos cerca de una calle y calcula qué tan segura es
CREATE OR REPLACE FUNCTION calcular_score_tramo(calle_geom GEOMETRY)
RETURNS NUMERIC AS $$
DECLARE
    score_base NUMERIC := 100.0; -- El tramo empieza siendo 100% seguro
    penalizacion NUMERIC := 0;
BEGIN
    -- Sumamos el TrustScore de los reportes "activos" a menos de 50 metros del tramo
    -- Multiplicamos por 0.5 para que cada reporte reste la mitad de su "peso" a la calle
    SELECT COALESCE(SUM(trust_score * 0.5), 0)
    INTO penalizacion
    FROM reportes
    WHERE estado = 'activo' 
    AND ST_DWithin(geom::geography, calle_geom::geography, 50);

    -- Restamos la penalización matemática al score base de la calle
    score_base := score_base - penalizacion;

    -- Garantizamos que la calle no tenga seguridad negativa
    IF score_base < 0 THEN score_base := 0; END IF;

    RETURN score_base;
END;
$$ LANGUAGE plpgsql;

-- 3. Función principal de Ruta Segura (Basada en Dijkstra Ponderado)
-- Nota: Requiere una tabla topológica llamada "calles" con columnas id, source, target y geom
CREATE OR REPLACE FUNCTION obtener_ruta_segura(nodo_origen INT, nodo_destino INT)
RETURNS TABLE (
    paso INT,
    tramo_id INT,
    score_seguridad NUMERIC,
    ruta_geom GEOMETRY
) AS $$
BEGIN
    RETURN QUERY
    WITH ruta_calculada AS (
        -- pgr_dijkstra evalúa todas las calles posibles
        -- El "costo" de la calle aumenta drásticamente si su score_tramo es bajo (peligroso)
        SELECT * FROM pgr_dijkstra(
            'SELECT id, source, target, 
                    (ST_Length(geom::geography) + ((100 - calcular_score_tramo(geom)) * 10)) AS cost 
             FROM calles',
            nodo_origen, 
            nodo_destino, 
            false
        )
    )
    -- Devolvemos la ruta como una colección de LineStrings con su calificación de seguridad por tramo
    SELECT 
        r.seq AS paso,
        r.edge AS tramo_id,
        calcular_score_tramo(c.geom) AS score_seguridad,
        c.geom AS ruta_geom
    FROM ruta_calculada r
    JOIN calles c ON r.edge = c.id
    ORDER BY r.seq;
END;
$$ LANGUAGE plpgsql;