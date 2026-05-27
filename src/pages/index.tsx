import { useMemo, useState } from "react";
import Navigation from "../components/Navigation";

function toInputValue(dt: string) {
  // input[type=datetime-local] ต้องรูปแบบ YYYY-MM-DDTHH:mm
  return dt.replace(" ", "T").slice(0, 16);
}

type SqlVariant = "consumer" | "corporate";

const CUST_DESC_OPTIONS = ["Agri", "Fishery", "Livestock", "Comsumer", "NonAgri"];
const CUST_TYPE_OPTIONS = ["500", "707", "708", "709", "710", "711"];

export default function Home() {
  const [from, setFrom] = useState("2025-12-01 00:00:00.000");
  const [to, setTo] = useState("2025-12-30 23:59:59.999");
  const [variant, setVariant] = useState<SqlVariant>("consumer");
  const [custDesc, setCustDesc] = useState("Agri");
  const [custTypes, setCustTypes] = useState<string[]>([...CUST_TYPE_OPTIONS]);
  const [isLoading, setIsLoading] = useState(false);
  const [lastMsg, setLastMsg] = useState<string>("");

  const custFilter = variant === "consumer" ? custDesc : custTypes.join(",");
  const corporateInvalid = variant === "corporate" && custTypes.length === 0;
  const sqlFileLabel =
    variant === "consumer" ? "sql/export_detail.sql" : "sql/export_detail_cap.sql";

  const exportUrl = useMemo(() => {
    const qs = new URLSearchParams({
      from,
      to,
      variant,
      custFilter,
      keyType: "assessment_no",
    });
    return `/api/export?${qs.toString()}`;
  }, [from, to, variant, custFilter]);

  const toggleCustType = (value: string) => {
    setCustTypes((prev) =>
      prev.includes(value) ? prev.filter((v) => v !== value) : [...prev, value]
    );
  };
  const selectAllCustTypes = () => setCustTypes([...CUST_TYPE_OPTIONS]);
  const clearCustTypes = () => setCustTypes([]);

  async function onExport() {
    setIsLoading(true);
    setLastMsg("");
    try {
      const res = await fetch(exportUrl);
      if (!res.ok) {
        const t = await res.text();
        throw new Error(t || `HTTP ${res.status}`);
      }
      const blob = await res.blob();
      const cd = res.headers.get("content-disposition") || "";
      const m = /filename="([^"]+)"/.exec(cd);
      const fileName = m?.[1] ?? "export.csv";

      const a = document.createElement("a");
      const url = window.URL.createObjectURL(blob);
      a.href = url;
      a.download = fileName;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);

      setLastMsg(`ดาวน์โหลดสำเร็จ: ${fileName}`);
    } catch (e: any) {
      setLastMsg(`Error: ${e?.message ?? String(e)}`);
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <>
      <Navigation />
      <main>
        <h1>Data Exporter</h1>
        <p>
          ดึงรายการ <code>assessment_no</code> จาก <code>cif.mas_assessment_answer</code> แล้วรัน query รายละเอียดเพื่อ export เป็น CSV
        </p>
        <p className="small" style={{ marginTop: 8 }}>
          ไฟล์ที่ได้จากเมนูนี้จะเป็น <b>File 1 (ตารางหลัก)</b> สำหรับนำไปใช้ใน CSV Merge Tool
        </p>

        <div className="card">
          <div className="row">
            <label>
              From (timestamp)
              <input
                type="datetime-local"
                value={toInputValue(from)}
                onChange={(e) => setFrom(e.target.value.replace("T", " ") + ":00.000")}
              />
              <small>ตัวอย่าง: 2025-12-01 00:00:00.000</small>
            </label>

            <label>
              To (timestamp)
              <input
                type="datetime-local"
                value={toInputValue(to)}
                onChange={(e) => setTo(e.target.value.replace("T", " ") + ":59.999")}
              />
              <small>ตัวอย่าง: 2025-12-30 23:59:59.999</small>
            </label>

            <label>
              SQL Variant
              <select value={variant} onChange={(e) => setVariant(e.target.value as SqlVariant)}>
                <option value="consumer">Consumer (export_detail.sql)</option>
                <option value="corporate">Corporate (export_detail_cap.sql)</option>
              </select>
              <small>เลือกไฟล์ SQL ที่ต้องการใช้ในการ export</small>
            </label>

            {variant === "consumer" ? (
              <label>
                Customer Description (cust_desc)
                <select value={custDesc} onChange={(e) => setCustDesc(e.target.value)}>
                  {CUST_DESC_OPTIONS.map((c) => (
                    <option key={c} value={c}>{c}</option>
                  ))}
                </select>
                <small>เลือกประเภทลูกค้า (cust_desc) สำหรับกรองข้อมูล</small>
              </label>
            ) : (
              <label>
                Customer Type (cust_type) — เลือกได้หลายค่า
                <div style={{ display: "flex", flexWrap: "wrap", gap: 12, marginTop: 6 }}>
                  {CUST_TYPE_OPTIONS.map((opt) => (
                    <label key={opt} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                      <input
                        type="checkbox"
                        checked={custTypes.includes(opt)}
                        onChange={() => toggleCustType(opt)}
                      />
                      {opt}
                    </label>
                  ))}
                </div>
                <div style={{ display: "flex", gap: 8, marginTop: 6 }}>
                  <button type="button" onClick={selectAllCustTypes}>Select All</button>
                  <button type="button" onClick={clearCustTypes}>Clear</button>
                </div>
                <small>
                  เลือกรหัสประเภทลูกค้า (cust_type) สำหรับ Corporate/Capital — ใช้ <code>ANY($3::text[])</code> ใน SQL
                </small>
                {corporateInvalid && (
                  <small style={{ color: "crimson" }}>กรุณาเลือกอย่างน้อย 1 ค่า</small>
                )}
              </label>
            )}

            <button onClick={onExport} disabled={isLoading || corporateInvalid}>
              {isLoading ? "กำลัง Export..." : "Export CSV"}
            </button>
          </div>

          <div style={{ marginTop: 12 }}>
            <small>API URL → <code>{sqlFileLabel}</code></small>
            <pre>{exportUrl}</pre>
            {lastMsg && <p><b>{lastMsg}</b></p>}
          </div>
        </div>

        <div className="card" style={{ marginTop: 12 }}>
          <div className="cardTitle">หมายเหตุ</div>
          <div className="small">
            <ul>
              <li>ระบบจะดึงข้อมูลจาก Database ตาม <code>{sqlFileLabel}</code></li>
              <li>ไฟล์ CSV ที่ได้สามารถนำไปใช้เป็น <b>File 1</b> ใน CSV Merge Tool</li>
              <li>ต้องตั้งค่า Database connection ใน <code>.env.local</code> ก่อนใช้งาน</li>
            </ul>
          </div>
        </div>
      </main>
    </>
  );
}
