-- SEMANA 9: Score de Seguridad Temporal

-- 1. Tabla historial_incidentes con franja horaria y día del evento
CREATE TABLE IF NOT EXISTS historial_incidentes (
    id SERIAL PRIMARY KEY,
    zona_id INTEGER, 
    dia_semana INTEGER CHECK (dia_semana BETWEEN 0 AND 6), -- 0=Domingo, 1=Lunes, ..., 6=Sábado
    franja_horaria INTEGER CHECK (franja_horaria BETWEEN 0 AND 23), -- Formato 24h
    nivel_gravedad NUMERIC NOT NULL,
    fecha_registro TIMESTAMP DEFAULT NOW()
);

-- 2. Función de perfil de riesgo histórico por hora del día para cada zona
CREATE OR REPLACE FUNCTION calcular_perfil_riesgo_historico(
    p_zona_id INTEGER, 
    p_dia_semana INTEGER, 
    p_franja_horaria INTEGER
)
RETURNS NUMERIC AS $$
DECLARE
    riesgo_promedio NUMERIC;
BEGIN
    SELECT COALESCE(AVG(nivel_gravedad), 0)
    INTO riesgo_promedio
    FROM historial_incidentes
    WHERE zona_id = p_zona_id 
      AND dia_semana = p_dia_semana 
      AND franja_horaria = p_franja_horaria;
      
    RETURN ROUND(riesgo_promedio, 2);
END;
$$ LANGUAGE plpgsql;

-- 3. Función que proyecta el riesgo esperado a una hora futura
CREATE OR REPLACE FUNCTION proyectar_riesgo_futuro(
    p_zona_id INTEGER, 
    fecha_futura TIMESTAMP
)
RETURNS NUMERIC AS $$
DECLARE
    v_dia_semana INTEGER;
    v_franja_horaria INTEGER;
    riesgo_proyectado NUMERIC;
BEGIN
    v_dia_semana := EXTRACT(DOW FROM fecha_futura);
    v_franja_horaria := EXTRACT(HOUR FROM fecha_futura);

    riesgo_proyectado := calcular_perfil_riesgo_historico(p_zona_id, v_dia_semana, v_franja_horaria);
    
    RETURN riesgo_proyectado;
END;
$$ LANGUAGE plpgsql;