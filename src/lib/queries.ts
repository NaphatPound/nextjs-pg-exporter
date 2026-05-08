import fs from "node:fs";
import path from "node:path";

let _getIdsSql: string | null = null;
let _exportDetailSql: string | null = null;

function readSqlOnce(rel: string): string {
  const p = path.join(process.cwd(), rel);
  return fs.readFileSync(p, "utf-8");
}

export function getIdsSql(): string {
  if (_getIdsSql) return _getIdsSql;
  _getIdsSql = readSqlOnce("sql/get_ids.sql");
  return _getIdsSql;
}

export function exportDetailSql(): string {
  if (_exportDetailSql) return _exportDetailSql;
  _exportDetailSql = readSqlOnce("sql/export_detail.sql");
  return _exportDetailSql;
}
