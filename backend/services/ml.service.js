// Implementación ligera de K-Means en JS puro — no hace falta traer una
// librería de ML pesada para clusterizar los pocos cientos/miles de
// puntos que va a tener esta app. Sin dependencias nuevas, funciona en
// cualquier runtime de Node.

/**
 * Convierte una hora (0-23) a un punto en el círculo unitario (seno,
 * coseno) en vez de usar el número crudo. Así 23:00 y 00:00 quedan cerca
 * en el espacio de features — con la hora cruda, K-Means los trataría
 * como los valores más lejanos posibles, cuando en realidad son casi el
 * mismo momento del día.
 */
const horaAFeature = (hora) => {
  const rad = (hora / 24) * 2 * Math.PI;
  return [Math.sin(rad), Math.cos(rad)];
};

const distancia2 = (a, b) => a.reduce((suma, v, i) => suma + (v - b[i]) ** 2, 0);

/**
 * K-Means clásico (asignar → recalcular centroides → repetir).
 * Inicializa los centroides tomando puntos espaciados del propio dataset
 * en vez de aleatorios — con pocos datos es más estable y determinístico
 * (mismo input, mismo resultado, útil para debug).
 */
const kmeans = (puntos, k, iteraciones = 25) => {
  if (puntos.length === 0) return { asignaciones: [], centroides: [] };

  const kReal = Math.min(k, puntos.length);
  const paso = Math.max(1, Math.floor(puntos.length / kReal));
  let centroides = Array.from({ length: kReal }, (_, i) => [...puntos[(i * paso) % puntos.length]]);
  let asignaciones = new Array(puntos.length).fill(0);

  for (let iter = 0; iter < iteraciones; iter++) {
    let cambio = false;

    for (let i = 0; i < puntos.length; i++) {
      let mejor = 0;
      let mejorDist = Infinity;
      for (let c = 0; c < kReal; c++) {
        const d = distancia2(puntos[i], centroides[c]);
        if (d < mejorDist) { mejorDist = d; mejor = c; }
      }
      if (asignaciones[i] !== mejor) { asignaciones[i] = mejor; cambio = true; }
    }

    const sumas = Array.from({ length: kReal }, () => new Array(puntos[0].length).fill(0));
    const conteos = new Array(kReal).fill(0);
    for (let i = 0; i < puntos.length; i++) {
      const c = asignaciones[i];
      conteos[c]++;
      puntos[i].forEach((v, d) => { sumas[c][d] += v; });
    }
    centroides = centroides.map((centro, c) =>
      conteos[c] > 0 ? sumas[c].map(s => s / conteos[c]) : centro
    );

    if (!cambio) break;
  }

  return { asignaciones, centroides };
};

// Con menos puntos que esto, K-Means no tiene con qué encontrar patrones
// reales (clusterizar 3-4 reportes en 3 grupos es ruido, no un patrón) —
// se usa la fórmula de reglas fijas de siempre como fallback.
const MIN_REPORTES_PARA_CLUSTERING = 12;
const K_CLUSTERS = 3; // bajo / medio / alto riesgo horario

/**
 * Puntaje de riesgo (0-10) para una hora específica, a partir de un
 * historial de reportes `[{hora, gravedad}]` — no le importa de dónde
 * salió ese historial (una zona pre-dibujada en `zonas_riesgo`, el área
 * de una ruta, etc.), así que zonas.controller.js (score de una zona) y
 * rutas.controller.js (score del trayecto en Ruta segura) comparten esta
 * misma lógica en vez de cada quien reimplementar su propio K-Means.
 */
const calcularScoreTemporal = (historico, horaNum) => {
  let score;
  let mlInfo = null;
  let metodo;

  if (historico.length >= MIN_REPORTES_PARA_CLUSTERING) {
    // ── Ruta ML: K-Means sobre (hora_sin, hora_cos, gravedad) ──
    const puntos = historico.map(h => [...horaAFeature(h.hora), h.gravedad]);
    const { asignaciones, centroides } = kmeans(puntos, K_CLUSTERS);

    // ¿A qué cluster horario pertenece la hora consultada? Comparamos
    // solo en el espacio (hora_sin, hora_cos) — la gravedad es justamente
    // lo que estamos prediciendo, no algo que ya sepamos de antemano para
    // la hora consultada.
    const featureHoraConsulta = horaAFeature(horaNum);
    let clusterCercano = 0;
    let mejorDist = Infinity;
    centroides.forEach((c, i) => {
      const d = distancia2(featureHoraConsulta, [c[0], c[1]]);
      if (d < mejorDist) { mejorDist = d; clusterCercano = i; }
    });

    const gravedadPromedio = centroides[clusterCercano][2];
    const tamanoCluster = asignaciones.filter(a => a === clusterCercano).length;

    score = Math.max(0, Math.min(10, Math.round((10 - gravedadPromedio * 7) * 10) / 10));
    metodo = 'kmeans';
    mlInfo = {
      cluster: clusterCercano,
      reportes_en_cluster: tamanoCluster,
      gravedad_promedio_cluster: Math.round(gravedadPromedio * 100) / 100,
      total_reportes_historicos: historico.length,
    };
  } else {
    // ── Fallback: reglas fijas (dataset insuficiente para clusterizar) ──
    const reportesEsaHora = historico.filter(h => h.hora === horaNum).length;
    const reportesGravesHora = historico.filter(h => h.hora === horaNum && h.gravedad >= 1.0).length;
    const horaMin = Math.max(0, horaNum - 1);
    const horaMax = Math.min(23, horaNum + 1);
    const reportesFranja = historico.filter(h => h.hora >= horaMin && h.hora <= horaMax).length;

    score = 10.0;
    score -= Math.min(reportesEsaHora * 1.5, 5.0);
    score -= Math.min(reportesGravesHora * 2.0, 4.0);
    score -= Math.min(reportesFranja * 0.3, 2.0);
    score = Math.max(0.0, Math.round(score * 10) / 10);
    metodo = 'reglas_fijas';
  }

  let franja;
  if (horaNum >= 6 && horaNum < 12) franja = 'mañana';
  else if (horaNum >= 12 && horaNum < 18) franja = 'tarde';
  else if (horaNum >= 18 && horaNum < 22) franja = 'noche temprana';
  else franja = 'madrugada';

  const nivelRiesgo = score >= 7 ? 'bajo' : score >= 4 ? 'medio' : 'alto';

  return { score, metodo, mlInfo, franja, nivelRiesgo, totalHistorico: historico.length };
};

/**
 * TrustScore general de una zona (0-10) a partir de conteos crudos —
 * misma fórmula que antes vivía copiada en zonas.controller.js y
 * rutas.controller.js. Se saca a una sola función pura para que ambos
 * comparten un único criterio y para poder probarla sin base de datos.
 */
const calcularTrustScore = ({ reportesGraves = 0, luminariasFundidas = 0, totalReportes = 0 }) => {
  let trustScore = 10.0;
  trustScore -= Math.min(reportesGraves * 1.5, 5.0);
  trustScore -= Math.min(luminariasFundidas * 0.5, 3.0);
  trustScore -= Math.min(totalReportes * 0.3, 2.0);
  trustScore = Math.max(0.0, Math.round(trustScore * 10) / 10);

  const nivelRiesgo = trustScore >= 7 ? 'bajo' : trustScore >= 4 ? 'medio' : 'alto';

  return { trustScore, nivelRiesgo };
};

module.exports = {
  kmeans, horaAFeature, distancia2,
  calcularScoreTemporal, MIN_REPORTES_PARA_CLUSTERING,
  calcularTrustScore,
};
