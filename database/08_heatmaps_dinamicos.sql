-- SEMANA 8: Heatmaps Dinámicos

-- 1. Procedimiento que recalcula las zonas de riesgo
CREATE OR REPLACE FUNCTION actualizar_heatmap_zonas_riesgo()
RETURNS TRIGGER AS $$
BEGIN
    -- Verificamos si el reporte entrante (o actualizado) está activo y tiene un TrustScore alto
    IF NEW.estado = 'activo' AND NEW.trust_score >= 75 THEN
        
        -- Actualizamos los polígonos del heatmap en zonas_riesgo automáticamente.
        -- Transformamos el punto del reporte en un polígono (buffer de 100 metros a la redonda).
        INSERT INTO zonas_riesgo (nivel, ultima_actualizacion, geom)
        VALUES (
            'Alto', 
            NOW(), 
            ST_Buffer(NEW.geom::geography, 100)::geometry
        );

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Trigger de BD para recalculación inmediata
-- Eliminamos el trigger si ya existe para evitar duplicados
DROP TRIGGER IF EXISTS trigger_recalcular_heatmap ON reportes;

-- Creamos el trigger que "escuchará" cualquier cambio en los reportes
CREATE TRIGGER trigger_recalcular_heatmap
AFTER INSERT OR UPDATE OF estado, trust_score
ON reportes
FOR EACH ROW
EXECUTE FUNCTION actualizar_heatmap_zonas_riesgo();