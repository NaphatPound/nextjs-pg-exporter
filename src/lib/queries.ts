import fs from "node:fs";
import path from "node:path";

export type SqlVariant = "consumer" | "corporate";

const cache: Record<string, string> = {};

function readSqlOnce(rel: string): string {
  if (cache[rel]) return cache[rel];
  const p = path.join(process.cwd(), rel);
  cache[rel] = fs.readFileSync(p, "utf-8");
  return cache[rel];
}

export function getIdsSql(variant: SqlVariant = "consumer"): string {
  return variant === "corporate"
    ? readSqlOnce("sql/get_ids_cap.sql")
    : readSqlOnce("sql/get_ids.sql");
}

export function exportDetailSql(variant: SqlVariant = "consumer"): string {
  return variant === "corporate"
    ? readSqlOnce("sql/export_detail_cap.sql")
    : readSqlOnce("sql/export_detail.sql");
}
