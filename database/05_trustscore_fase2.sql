-- SEMANA 5: TrustScore - Fase 2 (Validación Cruzada y Open Data)

-- 1. Crear tablas para validaciones de la comunidad y Open Data (Luminarias)
CREATE TABLE IF NOT EXISTS validaciones (
    id SERIAL PRIMARY KEY,
    reporte_id INT REFERENCES reportes(id),
    usuario_id INT REFERENCES usuarios(id),
    confirmado BOOLEAN, -- true si lo confirman, false si es falso
    timestamp TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS luminarias (
    id SERIAL PRIMARY KEY,
    estado VARCHAR(20), -- ej. 'encendida', 'apagada'
    geom GEOMETRY(Point, 4326)
);

-- 2. Insertar datos de prueba para validaciones y cruce geoespacial
INSERT INTO luminarias (estado, geom)
VALUES ('apagada', ST_SetSRID(ST_MakePoint(-98.2051, 19.0421), 4326));

INSERT INTO validaciones (reporte_id, usuario_id, confirmado)
VALUES (1, 2, true);

-- 3. Mega-Consulta de Validación Cruzada (Historial + Votos + Open Data)
SELECT 
    r.id AS reporte_id,
    r.categoria,
    -- Historial de fiabilidad del usuario reportante
    u.historial_confianza AS fiabilidad_creador,
    -- Conteo de votos de otros usuarios en la zona
    (SELECT COUNT(*) FROM validaciones v WHERE v.reporte_id = r.id AND v.confirmado = true) AS votos_a_favor,
    -- Cruce con Open Data: Luminarias apagadas a menos de 50 metros
    (SELECT COUNT(*) FROM luminarias l WHERE ST_DWithin(l.geom::geography, r.geom::geography, 50) AND l.estado = 'apagada') AS luminarias_apagadas_cercanas
FROM reportes r
JOIN usuarios u ON r.usuario_id = u.id
WHERE r.id = 1;