import type { NextApiRequest, NextApiResponse } from "next";
import { getPool } from "../../lib/db";
import { exportDetailSql, getIdsSql, type SqlVariant } from "../../lib/queries";
import { rowsToCsv } from "../../lib/csv";

type KeyType = "assessment_no" | "application_id";

function asString(v: any): string | null {
  if (typeof v === "string" && v.trim()) return v.trim();
  return null;
}

function safeFileDate(s: string) {
  return s.replace(/[: ]/g, "-").replace(/\..*$/, "");
}

function parseList(v: any): string[] {
  if (Array.isArray(v)) return v.map((s) => String(s).trim()).filter(Boolean);
  if (typeof v === "string") {
    return v.split(",").map((s) => s.trim()).filter(Boolean);
  }
  return [];
}

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== "GET") return res.status(405).send("Method Not Allowed");

  const from = asString(req.query.from);
  const to = asString(req.query.to);
  const variantRaw = asString(req.query.variant) ?? "consumer";
  const variant: SqlVariant = variantRaw === "corporate" ? "corporate" : "consumer";

  // Consumer: custFilter = single cust_desc string (e.g. "Agri")
  // Corporate: custFilter = comma-separated cust_type values → bound as text[] for PG ANY($3::text[])
  // Backward compat: accept the legacy `custDesc` param as a fallback.
  const custFilterRaw =
    asString(req.query.custFilter) ?? asString(req.query.custDesc);

  let custFilterParam: string | string[];
  let custFilterLabel: string;

  if (variant === "corporate") {
    const list = parseList(custFilterRaw);
    if (list.length === 0) {
      return res.status(400).send("Corporate variant requires at least one cust_type (custFilter)");
    }
    custFilterParam = list;
    custFilterLabel = list.join("-");
  } else {
    custFilterParam = custFilterRaw ?? "Agri";
    custFilterLabel = custFilterParam as string;
  }

  const keyType = (asString(req.query.keyType) as KeyType) ?? "assessment_no";

  if (!from || !to) return res.status(400).send("Missing from/to");
  if (keyType !== "assessment_no" && keyType !== "application_id") {
    return res.status(400).send("keyType must be assessment_no | application_id");
  }

  const pool = getPool();

  // 1) ดึงรายการ IDs (consumer: cust_desc scalar / corporate: cust_type[] array) — both bound as $3
  const idsSql = getIdsSql(variant);
  const idsResult = await pool.query(idsSql, [from, to, custFilterParam]);

  if (idsResult.rowCount === 0) {
    return res.status(200).send("No rows to export (IDs query returned 0).");
  }

  // 2) สำหรับแต่ละ ID: รัน query รายละเอียด
  //    detail SQL params: $1=from, $2=to, $3=assessment_no, $4=custFilter (same shape as above)
  const outRows: Record<string, any>[] = [];
  const detailSql = exportDetailSql(variant);

  for (const row of idsResult.rows) {
    const application_id = row.application_id as string | null;
    const assessment_no = row.assessment_no as string | null;

    const key = keyType === "assessment_no" ? assessment_no : application_id;
    if (!key) continue;

    try {
      const detailRes = await pool.query(detailSql, [from, to, assessment_no, custFilterParam]);

      if (detailRes.rowCount === 0) {
        // ถ้าอยากให้มี row แจ้งเตือน ให้ push error row แทนได้
        continue;
      }

      for (const r of detailRes.rows) {
        outRows.push({
          application_id,
          assessment_no,
          ...r,
        });
      }
    } catch (e: any) {
      // เก็บ error เป็นแถวหนึ่ง (กันหลุดทั้งไฟล์)
      outRows.push({
        application_id,
        assessment_no,
        __error: e?.message ?? String(e),
      });
    }
  }

  const csv = rowsToCsv(outRows);
  const filename = `export_${variant}_${custFilterLabel}_${safeFileDate(from)}__${safeFileDate(to)}.csv`;

  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename=\"${filename}\"`);
  res.status(200).send(csv);
}
