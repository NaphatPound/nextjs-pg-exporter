import type { NextApiRequest, NextApiResponse } from "next";
import { getPool } from "../../lib/db";
import { exportDetailSql, getIdsSql } from "../../lib/queries";
import { rowsToCsv } from "../../lib/csv";

type KeyType = "assessment_no" | "application_id";

function asString(v: any): string | null {
  if (typeof v === "string" && v.trim()) return v.trim();
  return null;
}

function safeFileDate(s: string) {
  return s.replace(/[: ]/g, "-").replace(/\..*$/, "");
}

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== "GET") return res.status(405).send("Method Not Allowed");

  const from = asString(req.query.from);
  const to = asString(req.query.to);
  const keyType = (asString(req.query.keyType) as KeyType) ?? "assessment_no";

  if (!from || !to) return res.status(400).send("Missing from/to");
  if (keyType !== "assessment_no" && keyType !== "application_id") {
    return res.status(400).send("keyType must be assessment_no | application_id");
  }

  const pool = getPool();

  // 1) ดึงรายการ IDs
  const idsSql = getIdsSql();
  const idsResult = await pool.query(idsSql, [from, to]);

  if (idsResult.rowCount === 0) {
    return res.status(200).send("No rows to export (IDs query returned 0).");
  }

  // 2) สำหรับแต่ละ ID: รัน query รายละเอียด แล้วสะสม row สำหรับ output
  const outRows: Record<string, any>[] = [];
  const detailSql = exportDetailSql();

  for (const row of idsResult.rows) {
    const application_id = row.application_id as string | null;
    const assessment_no = row.assessment_no as string | null;

    const key = keyType === "assessment_no" ? assessment_no : application_id;
    if (!key) continue;

    try {
      // export_detail.sql ตั้งค่าให้ใช้ $3 = assessment_no (ค่าเริ่มต้น)
      // ถ้าคุณจะใช้ application_id ให้แก้ SQL ให้ใช้ $3 เป็น application_id และแก้ตรงนี้ให้ส่งค่าให้ถูก
      const detailRes = await pool.query(detailSql, [from, to, assessment_no]);

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
  const filename = `export_${safeFileDate(from)}__${safeFileDate(to)}.csv`;

  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename=\"${filename}\"`);
  res.status(200).send(csv);
}
