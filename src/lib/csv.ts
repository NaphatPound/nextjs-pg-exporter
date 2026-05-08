import { stringify } from "csv-stringify/sync";

export function rowsToCsv(rows: Record<string, any>[]): string {
  if (rows.length === 0) return "";

  // สร้าง header จาก key ของแถวแรก (คงลำดับตามที่ driver คืนมา)
  const columns = Object.keys(rows[0]);

  const csv = stringify(rows, {
    header: true,
    columns,
    quoted: true,
    record_delimiter: "windows",
  });

  // ใส่ BOM กัน Excel เปิดภาษาไทยเพี้ยน
  return "\ufeff" + csv;
}
