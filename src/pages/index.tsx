import { useMemo, useState } from "react";
import Navigation from "../components/Navigation";

function toInputValue(dt: string) {
  // input[type=datetime-local] ต้องรูปแบบ YYYY-MM-DDTHH:mm
  return dt.replace(" ", "T").slice(0, 16);
}

export default function Home() {
  const [from, setFrom] = useState("2025-12-01 00:00:00.000");
  const [to, setTo] = useState("2025-12-30 23:59:59.999");
  const [isLoading, setIsLoading] = useState(false);
  const [lastMsg, setLastMsg] = useState<string>("");

  const exportUrl = useMemo(() => {
    const qs = new URLSearchParams({
      from,
      to,
      keyType: "assessment_no",
    });
    return `/api/export?${qs.toString()}`;
  }, [from, to]);

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

            <button onClick={onExport} disabled={isLoading}>
              {isLoading ? "กำลัง Export..." : "Export CSV"}
            </button>
          </div>

          <div style={{ marginTop: 12 }}>
            <small>API URL:</small>
            <pre>{exportUrl}</pre>
            {lastMsg && <p><b>{lastMsg}</b></p>}
          </div>
        </div>
      </main>
    </>
  );
}
