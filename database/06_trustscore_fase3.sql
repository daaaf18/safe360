-- ==========================================
-- SEMANA 6: TrustScore - Fase 3 (Asignación de Score)
-- ==========================================

-- 1. Tabla de configuraciones para el umbral dinámico
CREATE TABLE IF NOT EXISTS configuraciones (
    parametro VARCHAR(50) PRIMARY KEY,
    valor NUMERIC NOT NULL,
    descripcion TEXT
);

-- Insertamos el umbral inicial (75 puntos)
INSERT INTO configuraciones (parametro, valor, descripcion)
VALUES ('umbral_trustscore', 75.00, 'Puntaje mínimo (0-100) para activación automática')
ON CONFLICT (parametro) DO NOTHING;

-- 2. Función para calcular el Score Final y decidir el estado
CREATE OR REPLACE FUNCTION calcular_trustscore_final(id_del_reporte INT)
RETURNS VOID AS $$
DECLARE
    score_final NUMERIC := 0;
    umbral_actual NUMERIC;
    fiabilidad_usuario NUMERIC;
    votos_positivos INT;
    votos_negativos INT;
    luminarias_rotas INT;
BEGIN
    -- Obtenemos el umbral
    SELECT valor INTO umbral_actual FROM configuraciones WHERE parametro = 'umbral_trustscore';

    -- Extraemos variables
    SELECT 
        COALESCE(u.historial_confianza, 1.0),
        (SELECT COUNT(*) FROM validaciones v WHERE v.reporte_id = r.id AND v.confirmado = true),
        (SELECT COUNT(*) FROM validaciones v WHERE v.reporte_id = r.id AND v.confirmado = false),
        (SELECT COUNT(*) FROM luminarias l WHERE ST_DWithin(l.geom::geography, r.geom::geography, 50) AND l.estado = 'apagada')
    INTO 
        fiabilidad_usuario, votos_positivos, votos_negativos, luminarias_rotas
    FROM reportes r
    JOIN usuarios u ON r.usuario_id = u.id
    WHERE r.id = id_del_reporte;

    -- Fórmula
    score_final := (fiabilidad_usuario * 5.0) + (votos_positivos * 15.0) - (votos_negativos * 15.0) + (luminarias_rotas * 10.0);

    -- Límites
    IF score_final > 100 THEN score_final := 100; END IF;
    IF score_final < 0 THEN score_final := 0; END IF;

    -- Integración vs Cola de Revisión
    IF score_final >= umbral_actual THEN
        UPDATE reportes SET trust_score = score_final, estado = 'activo' WHERE id = id_del_reporte;
    ELSE
        UPDATE reportes SET trust_score = score_final, estado = 'en_revision' WHERE id = id_del_reporte;
    END IF;
END;
$$ LANGUAGE plpgsql;