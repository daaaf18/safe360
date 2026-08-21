-- SEMANA 5: TrustScore - Fase 2 (Validación Cruzada y Open Data)

-- 1. Tabla de validaciones comunitarias (votos de usuarios)
CREATE TABLE IF NOT EXISTS validaciones (
    id SERIAL PRIMARY KEY,
    reporte_id INTEGER REFERENCES reportes(id) ON DELETE CASCADE,
    usuario_id INTEGER REFERENCES usuarios(id) ON DELETE CASCADE,
    confirmado BOOLEAN NOT NULL, -- true = confirma el reporte, false = lo rechaza
    created_at TIMESTAMP DEFAULT NOW()
);

-- 2. Consulta de validación cruzada completa
-- Cruza votos de usuarios + fiabilidad del reportante + luminarias apagadas cercanas
SELECT 
    r.id AS reporte_id,
    r.categoria,
    r.descripcion,
    r.estado,
    -- Historial de fiabilidad del usuario reportante
    u.historial_confianza AS fiabilidad_creador,
    -- Votos a favor de otros usuarios
    (SELECT COUNT(*) 
     FROM validaciones v 
     WHERE v.reporte_id = r.id AND v.confirmado = true) AS votos_a_favor,
    -- Votos en contra
    (SELECT COUNT(*) 
     FROM validaciones v 
     WHERE v.reporte_id = r.id AND v.confirmado = false) AS votos_en_contra,
    -- Luminarias apagadas a menos de 100 metros (Open Data real)
    (SELECT COUNT(*) 
     FROM luminarias l 
     WHERE ST_DWithin(l.geom::geography, r.geom::geography, 100) 
     AND l.estado = 'fundida') AS luminarias_fundidas_cercanas
FROM reportes r
JOIN usuarios u ON r.usuario_id = u.id
WHERE r.estado = 'pendiente'
ORDER BY r.id DESC;

-- 3. Función para calcular TrustScore de un reporte
-- Pondera: fiabilidad del usuario (30%) + votos (50%) + Open Data (20%)
CREATE OR REPLACE FUNCTION calcular_trust_score(p_reporte_id INTEGER)
RETURNS FLOAT AS $$
DECLARE
    fiabilidad FLOAT;
    votos_favor INT;
    votos_contra INT;
    luminarias_fundidas INT;
    score FLOAT;
BEGIN
    -- Obtener fiabilidad del usuario reportante
    SELECT u.historial_confianza INTO fiabilidad
    FROM reportes r JOIN usuarios u ON r.usuario_id = u.id
    WHERE r.id = p_reporte_id;

    -- Contar votos
    SELECT 
        COUNT(*) FILTER (WHERE confirmado = true),
        COUNT(*) FILTER (WHERE confirmado = false)
    INTO votos_favor, votos_contra
    FROM validaciones WHERE reporte_id = p_reporte_id;

    -- Contar luminarias fundidas cercanas
    SELECT COUNT(*) INTO luminarias_fundidas
    FROM luminarias l
    JOIN reportes r ON r.id = p_reporte_id
    WHERE ST_DWithin(l.geom::geography, r.geom::geography, 100)
    AND l.estado = 'fundida';

    -- Calcular score ponderado (0.0 a 1.0)
    score := (COALESCE(fiabilidad, 0.5) * 0.30)
           + (LEAST(COALESCE(votos_favor, 0), 10) / 10.0 * 0.50)
           + (LEAST(COALESCE(luminarias_fundidas, 0), 3) / 3.0 * 0.20);

    -- Penalizar por votos en contra
    score := score - (LEAST(COALESCE(votos_contra, 0), 5) / 5.0 * 0.20);

    RETURN GREATEST(0.0, LEAST(1.0, score));
END;
$$ LANGUAGE plpgsql;
