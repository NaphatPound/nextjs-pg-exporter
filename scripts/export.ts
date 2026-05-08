import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import { Pool } from "pg";
import { stringify } from "csv-stringify/sync";

function must(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

function parseArg(name: string): string | null {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return null;
  return process.argv[idx + 1] ?? null;
}

function safeFileDate(s: string) {
  return s.replace(/[: ]/g, "-").replace(/\..*$/, "");
}

function readSql(rel: string) {
  return fs.readFileSync(path.join(process.cwd(), rel), "utf-8");
}

async function main() {
  const from = parseArg("--from") ?? "2025-12-01 00:00:00.000";
  const to = parseArg("--to") ?? "2025-12-30 23:59:59.999";
  
  console.log("DB_PASSWORD length:", process.env.DB_PASSWORD?.length);

  const pool = new Pool({
    host: must("DB_HOST"),
    port: Number(process.env.DB_PORT ?? "5432"),
    database: must("DB_NAME"),
    user: must("DB_USER"),
    password: must("DB_PASSWORD"),
    max: Number(process.env.DB_POOL_MAX ?? "5"),
    idleTimeoutMillis: Number(process.env.DB_POOL_IDLE_MS ?? "30000"),
    ssl: (process.env.DB_SSL ?? "false").toLowerCase() === "true" ? { rejectUnauthorized: false } : undefined,
  });

  const idsSql = readSql("sql/get_ids.sql");
  const detailSql = readSql("sql/export_detail.sql");

  const ids = await pool.query(idsSql, [from, to]);
  console.log(`IDs: ${ids.rowCount}`);

  const out: Record<string, any>[] = [];

  for (const r of ids.rows) {
    const application_id = r.application_id as string | null;
    const assessment_no = r.assessment_no as string | null;
    if (!assessment_no) continue;

    try {
      const detail = await pool.query(detailSql, [from, to, assessment_no]);
      for (const row of detail.rows) {
        out.push({ application_id, assessment_no, ...row });
      }
    } catch (e: any) {
      out.push({ application_id, assessment_no, __error: e?.message ?? String(e) });
    }
  }

  const columns = out.length ? Object.keys(out[0]) : ["__empty"];
  const csv = "\ufeff" + stringify(out, { header: true, columns, quoted: true, record_delimiter: "windows" });

  const outDir = path.join(process.cwd(), "exports");
  fs.mkdirSync(outDir, { recursive: true });
  const filename = `export_${safeFileDate(from)}__${safeFileDate(to)}.csv`;
  const outPath = path.join(outDir, filename);
  fs.writeFileSync(outPath, csv, "utf-8");
  console.log(`Wrote: ${outPath}`);

  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
