-- sql/get_ids_cap.sql
-- ดึงรายการ (application_id, assessment_no) สำหรับ Corporate/Capital (filter by cust_type[])
SELECT DISTINCT
  d.application_id,
  d.assessment_no
FROM cif.mas_assessment_answer d
WHERE d.approved_date BETWEEN $1::timestamp AND ($2::timestamp + interval '1 millisecond')
  AND d.is_export_csv = true
  AND d.cust_type::text = ANY($3::text[])
ORDER BY d.application_id;
