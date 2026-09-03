const {
  horaAFeature,
  distancia2,
  kmeans,
  calcularScoreTemporal,
  calcularTrustScore,
  MIN_REPORTES_PARA_CLUSTERING,
} = require('../ml.service');

describe('horaAFeature', () => {
  test('23:00 y 00:00 quedan cerca en el espacio de features (el punto central de todo esto)', () => {
    const f23 = horaAFeature(23);
    const f0 = horaAFeature(0);
    const distanciaMedianoche = Math.sqrt(distancia2(f23, f0));

    // La hora cruda (23 vs 0) diría que están a 23 unidades de distancia —
    // en el círculo deben estar prácticamente pegadas.
    expect(distanciaMedianoche).toBeLessThan(0.3);
  });

  test('12:00 y 00:00 son las horas más opuestas del día → deben quedar lejos', () => {
    const f12 = horaAFeature(12);
    const f0 = horaAFeature(0);
    const d = Math.sqrt(distancia2(f12, f0));
    expect(d).toBeCloseTo(2, 1); // extremos opuestos del círculo unitario
  });

  test('siempre regresa un punto sobre el círculo unitario', () => {
    for (let h = 0; h < 24; h++) {
      const [sin, cos] = horaAFeature(h);
      expect(sin * sin + cos * cos).toBeCloseTo(1, 5);
    }
  });
});

describe('kmeans', () => {
  test('con 0 puntos no truena, regresa listas vacías', () => {
    const { asignaciones, centroides } = kmeans([], 3);
    expect(asignaciones).toEqual([]);
    expect(centroides).toEqual([]);
  });

  test('separa dos grupos obviamente distintos en clusters distintos', () => {
    const grupoA = [[0, 0], [0.1, 0.1], [-0.1, 0]];
    const grupoB = [[10, 10], [10.1, 9.9], [9.9, 10]];
    const puntos = [...grupoA, ...grupoB];

    const { asignaciones } = kmeans(puntos, 2);

    // Los 3 primeros (grupo A) deben compartir cluster entre sí, distinto
    // al de los últimos 3 (grupo B).
    expect(asignaciones[0]).toBe(asignaciones[1]);
    expect(asignaciones[1]).toBe(asignaciones[2]);
    expect(asignaciones[3]).toBe(asignaciones[4]);
    expect(asignaciones[4]).toBe(asignaciones[5]);
    expect(asignaciones[0]).not.toBe(asignaciones[3]);
  });

  test('es determinístico: mismo input, mismo resultado siempre', () => {
    const puntos = [[1, 2], [3, 1], [8, 9], [7, 8], [0, 0], [9, 9]];
    const r1 = kmeans([...puntos.map(p => [...p])], 3);
    const r2 = kmeans([...puntos.map(p => [...p])], 3);
    expect(r1.asignaciones).toEqual(r2.asignaciones);
    expect(r1.centroides).toEqual(r2.centroides);
  });

  test('si k es mayor que el número de puntos, no truena', () => {
    const { centroides } = kmeans([[1, 1], [2, 2]], 5);
    expect(centroides.length).toBe(2);
  });
});

describe('calcularScoreTemporal', () => {
  test('con menos de 12 reportes usa reglas_fijas, no kmeans', () => {
    const historico = [
      { hora: 22, gravedad: 1.0 },
      { hora: 22, gravedad: 1.0 },
      { hora: 3, gravedad: 0.5 },
    ];
    const resultado = calcularScoreTemporal(historico, 22);
    expect(resultado.metodo).toBe('reglas_fijas');
    expect(resultado.mlInfo).toBeNull();
  });

  test('con 12 o más reportes usa kmeans', () => {
    const historico = Array.from({ length: MIN_REPORTES_PARA_CLUSTERING }, (_, i) => ({
      hora: i % 24,
      gravedad: i % 2 === 0 ? 1.0 : 0.5,
    }));
    const resultado = calcularScoreTemporal(historico, 12);
    expect(resultado.metodo).toBe('kmeans');
    expect(resultado.mlInfo).not.toBeNull();
    expect(resultado.mlInfo.total_reportes_historicos).toBe(MIN_REPORTES_PARA_CLUSTERING);
  });

  test('sin historial, el score siempre es el máximo (10) por reglas fijas', () => {
    const resultado = calcularScoreTemporal([], 15);
    expect(resultado.score).toBe(10);
    expect(resultado.metodo).toBe('reglas_fijas');
    expect(resultado.nivelRiesgo).toBe('bajo');
  });

  test('muchos reportes graves a la misma hora bajan el score a alto riesgo', () => {
    const historico = Array.from({ length: 6 }, () => ({ hora: 23, gravedad: 1.0 }));
    const resultado = calcularScoreTemporal(historico, 23);
    expect(resultado.score).toBeLessThan(4);
    expect(resultado.nivelRiesgo).toBe('alto');
  });

  test('el score nunca sale del rango 0-10, sin importar cuántos reportes haya', () => {
    const historico = Array.from({ length: 50 }, () => ({ hora: 23, gravedad: 1.0 }));
    const resultado = calcularScoreTemporal(historico, 23);
    expect(resultado.score).toBeGreaterThanOrEqual(0);
    expect(resultado.score).toBeLessThanOrEqual(10);
  });

  test('clasifica correctamente la franja del día', () => {
    expect(calcularScoreTemporal([], 8).franja).toBe('mañana');
    expect(calcularScoreTemporal([], 14).franja).toBe('tarde');
    expect(calcularScoreTemporal([], 19).franja).toBe('noche temprana');
    expect(calcularScoreTemporal([], 2).franja).toBe('madrugada');
  });
});

describe('calcularTrustScore', () => {
  test('sin ningún reporte ni luminaria fundida, score máximo y riesgo bajo', () => {
    const { trustScore, nivelRiesgo } = calcularTrustScore({});
    expect(trustScore).toBe(10);
    expect(nivelRiesgo).toBe('bajo');
  });

  test('reportes graves pesan más que luminarias fundidas', () => {
    const soloGraves = calcularTrustScore({ reportesGraves: 2, luminariasFundidas: 0, totalReportes: 2 });
    const soloLuminarias = calcularTrustScore({ reportesGraves: 0, luminariasFundidas: 2, totalReportes: 0 });
    expect(soloGraves.trustScore).toBeLessThan(soloLuminarias.trustScore);
  });

  test('el score nunca baja de 0 aunque los conteos sean altísimos', () => {
    const { trustScore } = calcularTrustScore({
      reportesGraves: 999, luminariasFundidas: 999, totalReportes: 999,
    });
    expect(trustScore).toBe(0);
  });

  test('los niveles de riesgo respetan los mismos cortes que el resto de la app (7 y 4)', () => {
    // score 10 → bajo (0 reportes/luminarias)
    expect(calcularTrustScore({ reportesGraves: 0, luminariasFundidas: 0, totalReportes: 0 }).nivelRiesgo).toBe('bajo');
    // score 5.5 (penalización de 4.5 por 3 reportes graves) → medio
    expect(calcularTrustScore({ reportesGraves: 3, luminariasFundidas: 0, totalReportes: 0 }).nivelRiesgo).toBe('medio');
    // score 3 (penalización tope de graves + tope de total) → alto
    expect(calcularTrustScore({ reportesGraves: 4, luminariasFundidas: 0, totalReportes: 10 }).nivelRiesgo).toBe('alto');
  });
});
