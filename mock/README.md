# Mock CSV Files - ทดสอบฟีเจอร์ CSV Merge

ไฟล์ทดสอบสำหรับหน้า `/csv-merge` ที่มี **2 Output Modes** แยกกัน:
- **Replace** — แทนค่าใน File 1 ด้วย File 2 (พฤติกรรมเดิม)
- **Insert After** — เลือกแค่ key, คอลัมน์ที่เหลือใน File 2 จะ insert ต่อท้าย key column ใน File 1 อัตโนมัติ

## ไฟล์

> ⚠ **กติกาข้อมูล**: คอลัมน์ที่เป็น key ของทั้ง 2 ไฟล์มีค่า**ไม่ซ้ำกัน**ภายในไฟล์ตัวเอง
> - `file1.csv`: `a` (A001..A010), `b` (B001..B010), `c` (C001..C010) — unique ทุกตัว
> - `file2.csv`: `key_a` (A001..A009), `key_b` (B001..B009), `key_c` (C001..C009) — unique ทุกตัว
>
> ทำให้สามารถใช้ key เดียว (เช่น `a` ↔ `key_a`) ก็ match แถวได้ถูกต้อง

### `file1.csv` (ไฟล์หลัก) - 10 แถว, 8 คอลัมน์
```
a, b, c, customer_name, score, grade, status, comment
```

### `file2.csv` (ไฟล์แก้ไข) - 9 แถว, 9 คอลัมน์ (ขาดแถว A010 เพื่อทดสอบ FALSE)
```
key_a, key_b, extra_inserted_1, key_c, reviewer, new_score, extra_inserted_2, new_grade, new_status
```

---

## ทดสอบ Mode 1: **Replace**

1. เปิด http://localhost:3000/csv-merge
2. อัปโหลด `file1.csv` → ไฟล์ 1, `file2.csv` → ไฟล์ 2
3. เลือก **Output Mode = Replace**
4. ตั้งค่า mapping:

| File 1 (Target) | File 2 (Source) | Is Key? |
| --------------- | --------------- | ------- |
| a               | key_a           | ✅      |
| b               | key_b           | ✅      |
| c               | key_c           | ✅      |
| score           | new_score       | ❌      |
| grade           | new_grade       | ❌      |
| status          | new_status      | ❌      |

5. กด **Merge + Export Excel**

**ผลที่คาดหวัง** - ชีต Merged คอลัมน์: `a, b, c, customer_name, score, grade, status, comment, VALIDATION`
- 🟢 เขียว: cell ที่ค่าเปลี่ยนจาก file 1 และตรงกับ file 2
- 🔴 แดง: cell ที่ค่าไม่เปลี่ยน หรือ key ไม่ match
- VALIDATION = FALSE สำหรับแถว C010 (ไม่มีใน file 2)

---

### 🆕 Conditional Replace (per-row, เฉพาะ Replace mode)

ใช้ **`file2_conditional.csv`** (ใหม่) คู่กับ `file1.csv` เดิม

**กลไก**: แต่ละ replace row มีช่อง **Cond?** (checkbox) — ถ้าติ๊ก จะมีช่อง **Cond Col (F2)** + **When = ?** ให้ตั้งเงื่อนไขเฉพาะแถวนั้น (rule นั้น) เท่านั้น Rule ที่ไม่ติ๊ก = catch-all (apply เสมอเมื่อมาถึง). ถ้ามีหลาย rules ต่อ F1 col → first match wins.

#### โครงสร้าง `file2_conditional.csv` (9 แถว, 9 คอลัมน์)
```
key_a, key_b, key_c, customer_tier, score_premium, score_standard, score_basic, grade_final, status_final
```

- `customer_tier` มี 3 ค่า: **PREMIUM, STANDARD, BASIC**
- `score_*` มี 3 คอลัมน์ (ค่าต่างกันตาม tier) — ทดสอบ **conditional replace ที่ target เดียว (`score`) มีหลาย rule**
- `grade_final`, `status_final` — ทดสอบ **fallback rule** (replace ทุกแถวไม่มีเงื่อนไข)

#### ขั้นตอนทดสอบ

1. เลือก **Output Mode = Replace**
2. อัปโหลด `file1.csv` → ไฟล์ 1, `file2_conditional.csv` → ไฟล์ 2
3. ตั้ง mapping (ใช้ checkbox **Cond?** ในแต่ละ row ที่ต้องการเงื่อนไข):

| File 1 | File 2          | Is Key? | Cond? | Cond Col (F2)   | When = ?    |
| ------ | --------------- | ------- | ----- | --------------- | ----------- |
| a      | key_a           | ✅      | —     | —               | —           |
| b      | key_b           | ✅      | —     | —               | —           |
| c      | key_c           | ✅      | —     | —               | —           |
| score  | score_premium   |         | ✅    | `customer_tier` | `PREMIUM`   |
| score  | score_standard  |         | ✅    | `customer_tier` | `STANDARD`  |
| score  | score_basic     |         | ✅    | `customer_tier` | `BASIC`     |
| grade  | grade_final     |         | ❌    | —               | —           |
| status | status_final    |         | ❌    | —               | —           |

5. Merge + Export

#### ผลที่คาดหวัง

| แถว  | tier     | score (file1→merged) | grade  | status   | สีในเซลล์ score |
| ---- | -------- | -------------------- | ------ | -------- | ---------------- |
| A001 | PREMIUM  | 75 → **95**          | B → A  | APPROVED | 🟢 เขียว         |
| A002 | PREMIUM  | 82 → **92**          | A → A  | APPROVED | 🟢 เขียว         |
| A003 | STANDARD | 65 → **68**          | C → B  | PENDING → APPROVED | 🟢 เขียว |
| A004 | STANDARD | 70 → **70** (เท่าเดิม) | B → B | APPROVED | 🟢 เขียว         |
| A005 | BASIC    | 55 → **50**          | D → C  | REJECTED → PENDING | 🟢 เขียว |
| A006 | PREMIUM  | 88 → **98**          | A → A  | APPROVED | 🟢 เขียว         |
| A007 | STANDARD | 72 → **75**          | B → B  | PENDING → APPROVED | 🟢 เขียว |
| A008 | BASIC    | 60 → **52**          | C → C  | PENDING  | 🟢 เขียว         |
| A009 | STANDARD | 78 → **73**          | B → B  | APPROVED | 🟢 เขียว         |
| A010 | (ไม่มี) | 90 (คงเดิม)           | A      | APPROVED | ⚪ ไม่ลงสี + VALIDATION=**FALSE** |

#### ทดสอบ "ไม่มี rule match + ไม่มี fallback"

ลองลบ rule fallback ของ `grade` ออก แล้ว replace เฉพาะตอน `tier=PREMIUM`:
- แถว STANDARD/BASIC → grade คงค่าเดิมจาก file 1 + **ไม่ลงสี**

---

## ทดสอบ Mode 2: **Insert After**

1. เลือก **Output Mode = Insert After**
2. ตั้งค่า mapping — แยก **Key** (สำหรับ match) ออกจาก **Insert** (คอลัมน์ที่จะแทรกหลัง F1 col ที่ระบุ):

| File 1 (Target / Anchor) | File 2 (Source)  | Is Key? | ความหมาย                                    |
| ------------------------ | ---------------- | ------- | -------------------------------------------- |
| a                        | key_a            | ✅      | Key สำหรับ match                            |
| b                        | key_b            | ✅      | Key สำหรับ match                            |
| c                        | key_c            | ✅      | Key สำหรับ match                            |
| c                        | reviewer         | ❌      | Insert คอลัมน์ `reviewer` หลัง `c`          |
| c                        | extra_inserted_1 | ❌      | Insert คอลัมน์ `extra_inserted_1` หลัง `c`  |
| score                    | new_score        | ❌      | Insert คอลัมน์ `new_score` หลัง `score`     |
| grade                    | new_grade        | ❌      | Insert คอลัมน์ `new_grade` หลัง `grade`     |

3. กด **Merge + Export Excel**

**ผลที่คาดหวัง** - ชีต Merged คอลัมน์:
```
a, b, c, [reviewer, extra_inserted_1], customer_name,
score, [new_score], grade, [new_grade],
status, comment, VALIDATION
```

- 🟧 ส้ม: คอลัมน์ที่ insert (ตามตำแหน่งที่ระบุใน F1 anchor)
- VALIDATION = FALSE สำหรับแถว C010 → คอลัมน์ insert เป็นค่าว่าง
