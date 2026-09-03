const { GoogleGenerativeAI } = require('@google/generative-ai');
require('dotenv').config();

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: 'gemini-3.6-flash' });
// Mismo respaldo que chaty.service.js: gemini-3.6-flash confirmado con
// 503 "high demand" intermitentes — un modelo más ligero (también
// multimodal, probado con imagen real) para no rechazar evidencia válida
// solo porque el modelo principal está saturado en ese momento.
const modelRespaldo = genAI.getGenerativeModel({ model: 'gemini-3.1-flash-lite' });

const EXTENSIONES_IMAGEN = ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'];

const esImagen = (url) => {
  const limpia = url.split('?')[0].toLowerCase();
  return EXTENSIONES_IMAGEN.some(ext => limpia.endsWith(ext));
};

/**
 * Descarga la evidencia de un reporte y le pregunta a Gemini Vision si
 * muestra evidencia real de un incidente de ESE tipo específico
 * (`categoria`) antes de publicarlo.
 *
 * Solo valida imágenes — video necesitaría subirlo a la File API de
 * Gemini (proceso async de upload + polling), que no está implementado
 * todavía; los videos pasan sin validar.
 *
 * Si algo falla (red, Gemini caído, respuesta rara, timeout) RECHAZA el
 * reporte en vez de dejarlo pasar sin validar — antes esto fallaba
 * "abierto" (dejaba pasar cualquier foto, incluso una sin relación con la
 * categoría elegida, cuando Gemini no respondía a tiempo), lo cual es
 * justo el hueco que esto existe para tapar. Mejor pedirle al usuario que
 * reintente en un momento que publicar evidencia sin revisar.
 */
const validarEvidencia = async (evidenciaUrl, categoria = null) => {
  if (!evidenciaUrl || !esImagen(evidenciaUrl)) {
    return { valida: true, razon: null };
  }

  try {
    // Sin timeout, una imagen lenta de descargar o Gemini tardado se
    // queda colgando la petición de crear el reporte indefinidamente —
    // ya nos pasó probando esto mismo.
    const controller = new AbortController();
    const timeoutDescarga = setTimeout(() => controller.abort(), 10_000);
    let respuestaImg;
    try {
      respuestaImg = await fetch(evidenciaUrl, { signal: controller.signal });
    } finally {
      clearTimeout(timeoutDescarga);
    }
    if (!respuestaImg.ok) {
      return { valida: false, razon: 'No se pudo descargar la imagen para revisarla.' };
    }

    const buffer = Buffer.from(await respuestaImg.arrayBuffer());
    const mimeType = respuestaImg.headers.get('content-type') || 'image/jpeg';
    const base64 = buffer.toString('base64');

    const categoriaTexto = categoria
      ? `El usuario dice que esta foto es evidencia de: "${categoria}".`
      : 'El usuario no especificó una categoría.';

    const prompt = `Analiza esta imagen de un reporte ciudadano de seguridad urbana en México.
${categoriaTexto}

¿La imagen realmente muestra evidencia de ESE tipo específico de incidente? No basta con
que sea "algo relacionado con seguridad urbana en general" — tiene que corresponder a la
categoría que el usuario indicó. Por ejemplo: si dice "Robo" o "Acoso", debe verse algo
consistente con eso (no una banqueta vacía o un poste); si dice "Poca iluminación", debe
verse una zona oscura/mal iluminada; si dice "Accidente vial", debe verse un choque, daño
vial, o similar. Rechaza selfies sin contexto, capturas de pantalla no relacionadas, memes,
fotos genéricas, o fotos de un tipo de incidente distinto al que el usuario declaró.

Responde SOLO con este JSON, sin texto adicional ni markdown:
{"es_evidencia_valida": true o false, "razon": "explicación breve en español, máximo 20 palabras"}`;

    const contenido = [
      { text: prompt },
      { inlineData: { mimeType, data: base64 } },
    ];
    const generarConTimeout = (modeloUsar, timeoutMs) => Promise.race([
      modeloUsar.generateContent(contenido),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Gemini Vision tardó demasiado')), timeoutMs)
      ),
    ]);

    let result;
    try {
      result = await generarConTimeout(model, 12_000);
    } catch (errorPrimario) {
      console.error('gemini-3.6-flash (Vision) falló, reintentando con modelo de respaldo:', errorPrimario.message);
      result = await generarConTimeout(modelRespaldo, 10_000);
    }

    const texto = result.response.text().trim().replace(/```json|```/g, '').trim();
    const parsed = JSON.parse(texto);

    return {
      valida: parsed.es_evidencia_valida === true,
      razon: parsed.razon || null,
    };
  } catch (error) {
    console.error('Error validando evidencia con Gemini Vision:', error.message);
    return {
      valida: false,
      razon: 'No se pudo revisar la foto ahora mismo (el validador está saturado). Intenta de nuevo en un momento.',
    };
  }
};

module.exports = { validarEvidencia };
