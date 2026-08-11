-- SEMANA 4: TrustScore - Fase 1 (Validación GPS y Coherencia Geoespacial)

-- Función validadora que se ejecuta antes de insertar un reporte
CREATE OR REPLACE FUNCTION validar_gps_reporte()
RETURNS TRIGGER AS $$
DECLARE
    reportes_previos INT;
BEGIN
    -- 1. Validación de coordenadas inválidas (0,0)
    IF ST_X(NEW.geom) = 0 AND ST_Y(NEW.geom) = 0 THEN
        RAISE EXCEPTION 'Rechazo automatico: Coordenadas de GPS invalidas (0,0)';
    END IF;

    -- 2. Validación de límites geográficos del planeta
    IF ST_Y(NEW.geom) < -90 OR ST_Y(NEW.geom) > 90 OR 
       ST_X(NEW.geom) < -180 OR ST_X(NEW.geom) > 180 THEN
        RAISE EXCEPTION 'Rechazo automatico: Coordenadas fuera de los limites del planeta';
    END IF;

    -- 3. Validación de coherencia geoespacial (Anti-Spam)
    -- Evita que el mismo usuario reporte la misma categoría en el mismo lugar en menos de 10 minutos
    SELECT COUNT(id)
    INTO reportes_previos
    FROM reportes
    WHERE usuario_id = NEW.usuario_id
      AND categoria = NEW.categoria
      AND estado = 'pendiente'
      AND created_at > NOW() - INTERVAL '10 minutes'
      AND ST_DWithin(geom::geography, NEW.geom::geography, 50);

    IF reportes_previos > 0 THEN
        RAISE EXCEPTION 'Rechazo automatico: Ya enviaste este mismo reporte en esta area hace un momento';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear trigger que ejecuta la validación antes de cada INSERT en reportes
DROP TRIGGER IF EXISTS trigger_fase1_gps ON reportes;
CREATE TRIGGER trigger_fase1_gps
BEFORE INSERT ON reportes
FOR EACH ROW
EXECUTE FUNCTION validar_gps_reporte();
