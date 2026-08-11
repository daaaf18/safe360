-- SEMANA 3: Consultas Geoespaciales PostGIS


-- 1. Datos de prueba (Usuarios y Reportes)
INSERT INTO usuarios (id, nombre, email, password_hash, historial_confianza)
VALUES 
(1, 'Usuario Prueba 1', 'test1@safe360.com', 'hash_secreto_123', 9.99),
(2, 'Usuario Prueba 2', 'test2@safe360.com', 'hash_secreto_456', 8.50);

INSERT INTO reportes (usuario_id, categoria, trust_score, estado, timestamp, geom)
VALUES 
(1, 'Robo', 8.50, 'activo', NOW(), ST_SetSRID(ST_MakePoint(-98.2050, 19.0420), 4326)),
(2, 'Iluminacion', 9.00, 'activo', NOW(), ST_SetSRID(ST_MakePoint(-99.1332, 19.4326), 4326)),
(1, 'Asalto', 9.10, 'activo', NOW(), ST_SetSRID(ST_MakePoint(-98.2055, 19.0418), 4326)),
(2, 'Sospechoso', 8.20, 'activo', NOW(), ST_SetSRID(ST_MakePoint(-98.2045, 19.0422), 4326));

-- 2. Reportes cercanos en un radio configurable 
SELECT 
    id, categoria, trust_score, 
    ST_X(geom) AS longitud, ST_Y(geom) AS latitud,
    ROUND(ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(-98.2063, 19.0414), 4326)::geography)::numeric, 2) AS distancia_metros
FROM reportes
WHERE estado = 'activo'
  AND ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint(-98.2063, 19.0414), 4326)::geography, 500)
ORDER BY distancia_metros ASC;

-- 3. Zona de riesgo de prueba (Polígono)
INSERT INTO zonas_riesgo (nivel, ultima_actualizacion, geom)
VALUES (
    'Alto', NOW(),
    ST_SetSRID(ST_MakePolygon(ST_GeomFromText('LINESTRING(-98.2100 19.0400, -98.2000 19.0400, -98.2000 19.0450, -98.2100 19.0450, -98.2100 19.0400)')), 4326)
);

-- 4. Nivel de riesgo por polígono delimitado
SELECT id AS zona_id, nivel AS nivel_de_riesgo, ultima_actualizacion
FROM zonas_riesgo
WHERE ST_Intersects(geom, ST_SetSRID(ST_MakePoint(-98.2050, 19.0420), 4326));

-- 5.Densidad de reportes por área (Base para Heatmap dinámico)
SELECT 
    COUNT(id) AS cantidad_reportes,
    ROUND(AVG(trust_score)::numeric, 2) AS confianza_promedio,
    ST_X(ST_SnapToGrid(geom, 0.005)) AS centro_longitud,
    ST_Y(ST_SnapToGrid(geom, 0.005)) AS centro_latitud
FROM reportes
WHERE estado = 'activo'
GROUP BY ST_SnapToGrid(geom, 0.005)
ORDER BY cantidad_reportes DESC;