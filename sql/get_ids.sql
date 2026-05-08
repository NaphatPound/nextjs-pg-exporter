-- sql/get_ids.sql
-- ดึงรายการ (application_id, assessment_no) ที่ต้อง export
SELECT DISTINCT
  d.application_id,
  d.assessment_no
FROM cif.mas_assessment_answer d
WHERE d.approved_date BETWEEN $1::timestamp AND ($2::timestamp + interval '1 millisecond')
  AND d.is_export_csv = true
-- AND d.cust_desc = $3
ORDER BY d.application_id;
