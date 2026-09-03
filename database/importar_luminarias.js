const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '../backend/.env') });

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

async function importarLuminarias() {
  const csvPath = path.join(__dirname, 'Parque_Luminario__segundo_semestre_2025.csv');
  const contenido = fs.readFileSync(csvPath, 'utf8').replace(/^\uFEFF/, ''); // quitar BOM
  const lineas = contenido.split('\n').filter(l => l.trim() !== '');
  const datos = lineas.slice(1); // saltar encabezado

  console.log(`Importando ${datos.length} luminarias...`);

  let insertadas = 0;
  const BATCH = 500;

  for (let i = 0; i < datos.length; i += BATCH) {
    const lote = datos.slice(i, i + BATCH);
    const valores = [];
    const params = [];
    let idx = 1;

    for (const linea of lote) {
      const cols = linea.split(',');
      const calle   = cols[2]?.trim();
      const colonia = cols[3]?.trim();
      const lon     = parseFloat(cols[4]);
      const lat     = parseFloat(cols[5]);

      if (isNaN(lon) || isNaN(lat)) continue;

      valores.push(`($${idx}, $${idx+1}, ST_SetSRID(ST_MakePoint($${idx+2}, $${idx+3}), 4326))`);
      params.push(calle, colonia, lon, lat);
      idx += 4;
    }

    if (valores.length === 0) continue;

    await pool.query(
      `INSERT INTO luminarias (calle, colonia, geom) VALUES ${valores.join(',')}`,
      params
    );

    insertadas += valores.length;
    console.log(`  ${insertadas}/${datos.length} insertadas...`);
  }

  console.log(`\n✅ Importación completa: ${insertadas} luminarias insertadas.`);
  await pool.end();
}

importarLuminarias().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});