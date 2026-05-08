# Data Tools - Next.js Application

เครื่องมือรวม 2 ฟังก์ชันหลัก สำหรับจัดการข้อมูล CSV และ PostgreSQL

## ฟังก์ชันหลัก

### 1. PostgreSQL CSV Exporter
ดึงข้อมูลจาก PostgreSQL แล้ว Export เป็น CSV ตามช่วงวันที่ใน `cif.mas_assessment_answer`

### 2. CSV Merge Tool
อัปโหลด 2 ไฟล์ CSV → รวมข้อมูลด้วยคีย์ `a,b,c` → Export เป็น Excel 3 ชีต พร้อมสีเขียว/แดง

---

## การติดตั้ง

```bash
npm install
```

สร้างไฟล์ `.env.local` โดย copy จาก `.env.example` แล้วใส่รหัสผ่านจริง (สำหรับ PostgreSQL Exporter)

```bash
copy .env.example .env.local
```

---

## การใช้งาน

### รันแบบเว็บ

```bash
npm run dev
```

เข้าเว็บ: http://localhost:3000

- **หน้าหลัก (/)** - PostgreSQL Exporter
- **/csv-merge** - CSV Merge Tool

### รันแบบ CLI (PostgreSQL Exporter เท่านั้น)

```bash
npm run export -- --from "2025-12-01 00:00:00.000" --to "2025-12-30 23:59:59.999"
```

---

## PostgreSQL Exporter

### SQL ที่ใช้

- `sql/get_ids.sql` : ดึง (application_id, assessment_no) ที่เข้าเงื่อนไข
- `sql/export_detail.sql` : Query รายละเอียดตาม `assessment_no` (parameter: $1,$2,$3)

> ถ้าต้องเปลี่ยนจาก `assessment_no` ไปใช้ `application_id` ให้แก้ WHERE ใน `sql/export_detail.sql` แล้วแก้โค้ดส่วน call (ดู `src/lib/queries.ts`)

### หมายเหตุเรื่อง Excel ภาษาไทย

API จะใส่ UTF-8 BOM นำหน้าไฟล์ CSV ให้ Excel เปิดภาษาไทยไม่เพี้ยน

---

## CSV Merge Tool

### ฟีเจอร์

- อัปโหลด 2 ไฟล์ CSV (ไฟล์หลัก + ไฟล์แก้ไข)
- Merge ด้วยคีย์คอลัมน์ `a`, `b`, `c`
- Replace ค่าจากไฟล์ 2 ไปยังไฟล์ 1
- Export เป็น Excel 3 ชีต:
  - **Sheet1: File1** (ข้อมูลเดิม)
  - **Sheet2: File2** (ข้อมูลแก้ไข)
  - **Sheet3: Merged** (ข้อมูลที่รวมแล้ว + สีเขียว/แดง)

### กฎการลงสี (Sheet "Merged")

ใช้กับคอลัมน์ที่มาจากไฟล์ 2 เท่านั้น (ไม่รวมคีย์):
- **สีเขียว**: (File2 == Merged) AND (File2 != File1) → เซลล์ที่ถูกแก้ไข
- **สีแดง**: กรณีอื่นๆ

### ข้อกำหนด CSV

- ทั้ง 2 ไฟล์ต้องมีคอลัมน์ key: `a`, `b`, `c`
- จำนวนแถวต้องเท่ากัน และ key ต้องตรงกัน
- ไฟล์ 2 ควรมีคอลัมน์เป็น subset ของไฟล์ 1

---

## เทคโนโลยีที่ใช้

- **Next.js 14** (Pages Router)
- **React 18**
- **PostgreSQL** (pg)
- **papaparse** (CSV parsing)
- **xlsx-js-style** (Excel export with styling)
- **TypeScript**

---

## โครงสร้างโปรเจ็ค

```
src/
├── components/
│   └── Navigation.tsx      # เมนูนำทาง
├── pages/
│   ├── index.tsx           # PostgreSQL Exporter
│   ├── csv-merge.tsx       # CSV Merge Tool
│   └── api/
│       └── export.ts       # API สำหรับ export CSV
├── lib/
│   ├── db.ts               # PostgreSQL connection
│   ├── queries.ts          # SQL queries
│   └── csv.ts              # CSV utilities
└── styles/
    └── globals.css         # Global styles
```

