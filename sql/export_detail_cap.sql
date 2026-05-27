-- sql/export_detail_cap.sql
-- Parameters: $1 = from (timestamp), $2 = to (timestamp), $3 = assessment_no, $4 = cust_type[] (array)
WITH loan_scope AS (
	SELECT DISTINCT
        maa.cif_no,
        maa.application_id  as  loan_request_id,
        coalesce(s.sum_debt_loan_amount::numeric,0) as sum_debt_loan_amount,
        coalesce(cl.total_loan_request_amount::numeric,rt.total_loan_request_amount::numeric) as total_loan_request_amount,
		coalesce((maa.report_data->'variable'->'VC_243'->> 'data')::numeric,0) as total_dept_dbm,
        maa.assessment_no,
        maa.assessment_type,
        maa.report_data,
        maa.answer
    FROM cif.mas_assessment_answer maa
    left outer JOIN lps_corporate_loan.trn_loan_sll_detail s
      ON maa.cif_no = s.cif_no
      and maa.application_id  = s.loan_request_id
    left outer JOIN lps_corporate_loan.corp_loan_request_header cl
      ON maa.cif_no = cl.cif_no
      and maa.application_id  = cl.loan_request_id
    left outer JOIN lps_retail_loan.loan_request_header rt
      ON maa.cif_no = rt.cif_no
      and maa.application_id  = rt.loan_request_id
      WHERE maa.approved_date BETWEEN $1::timestamp AND ($2::timestamp + interval '1 millisecond')
      AND maa.is_export_csv = true
      AND maa.assessment_no = $3
      AND maa.cust_type::text = ANY($4::text[])
),
-- select * from loan_scope
-- ========================= OLD COLLATERAL =========================
old AS (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY NULL) AS rn,
        'old' AS ft,
        o.cif_id,
        o.loan_request_id,
        o.collateral_id,
        o.collateral_group,
        o.collateral_type ,
        o.appraisal_value,
        o.pledged_amount,
        o.create_datetime,
        o.all_collateral_id
    FROM (
        -- กลุ่ม 12–15 ใช้ pledged_amount จาก contract
        SELECT
            lf.cif_no::text      AS cif_id,
            lf.loan_request_id,
            t1.collateral_id,
            t1.collateral_group,
            t1.collateral_type ,
            t1.appraisal_value,
            t1.pledged_amount,
            t1.create_datetime,
            t1.all_collateral_id
        FROM loan_scope lf
        JOIN (
            select
                b.cif_id::text    AS cif_id,
                MAX(d.collateral_id) as collateral_id,
                c.collateral_group,
                MAX(c.collateral_type) as collateral_type,
                MAX(a.create_datetime) as create_datetime,
                MAX(d.appraisal_value) as appraisal_value,
                MAX(a.pledged_amount) as pledged_amount,
                STRING_AGG(d.collateral_id::text, '-' ORDER BY d.collateral_id) AS all_collateral_id
            FROM lps_collateral.trn_contract a
            LEFT JOIN lps_collateral.trn_contract_owner b
                   ON a.contract_no::text = b.contract_no::text
            LEFT JOIN lps_collateral.trn_collateral_contract c
                   ON c.contract_no = b.contract_no
            LEFT JOIN lps_collateral.trn_collateral d
                   ON d.collateral_no = c.collateral_no
            WHERE c.collateral_group IN ('12','13','14','15') 
            and a.contract_status = '0'
            GROUP BY b.cif_id, c.collateral_group, c.contract_id
        ) t1
          ON lf.cif_no = t1.cif_id
          -- WHERE t1.rowid = 1
          WHERE t1.create_datetime <= (
		      SELECT 
		          CASE 
		              -- Condition 1: Starts with DBM (Add 1ms + 7 hours)
		              WHEN lf.loan_request_id LIKE 'DBM%' 
		                   THEN MAX(update_datetime) + interval '1 millisecond' + interval '7 hour'
		              -- Condition 2: Others (Add only 1ms)
		              ELSE MAX(update_datetime) + interval '1 millisecond'
		          END
		      FROM cif.mas_assessment_answer 
		      WHERE assessment_no = lf.assessment_no
		  )
        UNION ALL
        -- กลุ่มอื่น ๆ (ไม่ใช่ 12–15) ใช้ appraisal_value จาก contract
        SELECT
            lf.cif_no::text      AS cif_id,
            lf.loan_request_id,
            t1.collateral_id,
            t1.collateral_group,
            t1.collateral_type ,
            t1.appraisal_value,
            t1.pledged_amount,
            t1.create_datetime,
            t1.all_collateral_id
        FROM loan_scope lf
        JOIN (
            SELECT
                b.cif_id::text    AS cif_id,
                d.collateral_id,
                c.collateral_group,
                c.collateral_type,
                a.create_datetime,
                d.appraisal_value,
                d.remain_value,
                c.pledged_amount,
                e.is_default_value_by_collateral_calculation as isNotApp,
                f.is_appraisal as isAPP,
                '' as all_collateral_id
            FROM lps_collateral.trn_contract a
            LEFT JOIN lps_collateral.trn_contract_owner b ON a.contract_no::text = b.contract_no::text
            LEFT JOIN lps_collateral.trn_collateral_contract c ON c.contract_no = b.contract_no
            LEFT JOIN lps_collateral.trn_collateral d ON d.collateral_no = c.collateral_no
            LEFT join lps_collateral.mas_collateral_contract_mapping e on e.collateral_group = d.collateral_group and e.collateral_type = d.collateral_type 
            		and e.collateral_subtype = d.collateral_sub_type
            LEFT join lps_collateral.mas_collateral_matrix f on f.collateral_group = d.collateral_group and f.collateral_type = d.collateral_type 
            		and f.collateral_subtype = d.collateral_sub_type
    		    WHERE c.collateral_group not IN ('12','13','14','15') 
    		    and a.contract_status = '0'
        ) t1
          ON lf.cif_no = t1.cif_id
          AND t1.create_datetime <= (
		      SELECT 
		          CASE 
		              -- Condition 1: Starts with DBM (Add 1ms + 7 hours)
		              WHEN lf.loan_request_id LIKE 'DBM%' 
		                   THEN MAX(update_datetime) + interval '1 millisecond' + interval '7 hour'
		              -- Condition 2: Others (Add only 1ms)
		              ELSE MAX(update_datetime) + interval '1 millisecond'
		          END
		      FROM cif.mas_assessment_answer 
		      WHERE assessment_no = lf.assessment_no
		  )
    ) o
),
-- select * from old
-- ========================= NEW COLLATERAL =========================
new AS (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY NULL) AS rn,
        'new' AS ft,
        n.cif_id,
        n.loan_request_id,
        n.collateral_id,
        n.collateral_group,
        n.collateral_type,
        n.appraisal_value,
        n.pledged_amount,
        n.all_collateral_id
    FROM (
        -- กลุ่ม 12–15 ใช้ obligation_value เป็น pledged_amount
        SELECT
            lf.cif_no::text      AS cif_id,
            lf.loan_request_id,
            t3.collateral_id,
            t3.collateral_group,
            t3.collateral_type,
            t3.appraisal_value,
            t3.pledged_amount,
            t3.all_collateral_id
        FROM loan_scope lf
        JOIN (
            SELECT
                b.cif_id::text              AS cif_id,
                x.loan_request_ref          AS loan_request_id,
                y.collateral_group,
                MAX(y.collateral_type) AS collateral_type,
                MAX(y.collateral_id) AS collateral_id,
                0::numeric                  AS appraisal_value,
                MAX(y.obligation_value::numeric) AS pledged_amount,
                STRING_AGG(y.collateral_id::text, '-' ORDER BY y.collateral_id) AS all_collateral_id
            FROM lps_collateral.trn_request_sheets x
            JOIN lps_collateral.trn_request_sheets_detail y
                 ON y.sheets_id_ref = x.sheets_id
            JOIN lps_collateral.trn_collateral z
                 ON z.collateral_id = y.collateral_id
            LEFT JOIN lps_collateral.trn_contract_owner b
                 ON y.sheets_id_ref::text = b.sheet_id_ref::text
            WHERE x.sheets_type      = 'LON'
              AND x.collateral_group IN ('12','13','14','15')
            GROUP BY b.cif_id, y.collateral_group, x.loan_request_ref, y.sheets_id_ref
        ) t3
          ON lf.cif_no          = t3.cif_id
         AND lf.loan_request_id = t3.loan_request_id
        UNION all
        -- กลุ่มเงินฝากคำ้ใช้ available_value
        SELECT
            lf.cif_no::text      AS cif_id,
            lf.loan_request_id,
            t5.collateral_id,
            t5.collateral_group,
            t5.collateral_type,
            t5.appraisal_value,
            t5.pledged_amount,
            t5.all_collateral_id
        FROM loan_scope lf
        JOIN (
            SELECT
                b.cif_id::text              AS cif_id,
                x.loan_request_ref          AS loan_request_id,
                y.collateral_group,
                y.collateral_type,
                y.collateral_id,
                CEIL(((det_elem->>'obligationValue')::numeric / NULLIF((det_elem->>'percentLTV')::numeric, 0) * 100 ) / 1000.0) * 1000 AS appraisal_value,
                0::numeric                  AS pledged_amount,
                '' as all_collateral_id
            FROM lps_collateral.trn_request_sheets x
            JOIN lps_collateral.trn_request_sheets_detail y
                 ON y.sheets_id_ref = x.sheets_id
            JOIN lps_collateral.trn_collateral z
                 ON z.collateral_id = y.collateral_id
            LEFT JOIN lps_collateral.trn_contract_owner b
                 ON y.sheets_id_ref::text = b.sheet_id_ref::text
            LEFT join lps_retail_loan.loan_collateral_history ch
            	 on x.loan_request_ref = ch.loan_request_id
            LEFT JOIN LATERAL jsonb_array_elements(
			    ch.loan_collateral_info->'collateral'->'selectedNonAppraisedCollateralGeneral'
			) AS gen(gen_elem) ON TRUE
			LEFT JOIN LATERAL jsonb_array_elements(
			    gen_elem->'detail'
			) AS det(det_elem) ON TRUE
            WHERE x.sheets_type          = 'LON'
              AND x.collateral_group IN ('20')
              and (det_elem->>'collateralId')::bigint = z.collateral_id
        ) t5
          ON lf.cif_no          = t5.cif_id
         AND lf.loan_request_id = t5.loan_request_id
        UNION all
        -- หลักประกันที่ไม่ประเมินราคา - ทั่วไป available_value
        SELECT
            lf.cif_no::text      AS cif_id,
            lf.loan_request_id,
            t5.collateral_id,
            t5.collateral_group,
            t5.collateral_type,
            t5.appraisal_value,
            t5.pledged_amount,
            t5.all_collateral_id
        FROM loan_scope lf
        JOIN (
            SELECT
                b.cif_id::text              AS cif_id,
                x.loan_request_ref          AS loan_request_id,
                y.collateral_group,
                y.collateral_type,
                y.collateral_id,
                (det_elem->>'availableValue')::numeric AS appraisal_value,
                0::numeric                  AS pledged_amount,
                '' as all_collateral_id
            FROM lps_collateral.trn_request_sheets x
            JOIN lps_collateral.trn_request_sheets_detail y
                 ON y.sheets_id_ref = x.sheets_id
            JOIN lps_collateral.trn_collateral z
                 ON z.collateral_id = y.collateral_id
            LEFT JOIN lps_collateral.mas_collateral_matrix mt on mt.collateral_group = z.collateral_group and mt.collateral_type = z.collateral_type 
            		and mt.collateral_subtype = z.collateral_sub_type
            LEFT JOIN lps_collateral.trn_contract_owner b
                 ON y.sheets_id_ref::text = b.sheet_id_ref::text
            LEFT join lps_retail_loan.loan_collateral_history ch
            	 on x.loan_request_ref = ch.loan_request_id
            LEFT JOIN LATERAL jsonb_array_elements(
			    ch.loan_collateral_info->'collateral'->'selectedNonAppraisedCollateralGeneral'
			) AS gen(gen_elem) ON TRUE
			LEFT JOIN LATERAL jsonb_array_elements(
			    gen_elem->'detail'
			) AS det(det_elem) ON TRUE
            WHERE x.sheets_type          = 'LON'
              AND mt.is_appraisal = false
              AND mt.is_guarantor = false
              AND x.collateral_group NOT IN ('12','13','14','15','20')
              AND (det_elem->>'collateralId')::bigint = z.collateral_id
        ) t5
          ON lf.cif_no          = t5.cif_id
         AND lf.loan_request_id = t5.loan_request_id
        UNION all
        -- กลุ่มอื่น ๆ ใช้ appraisal_value
        SELECT
            lf.cif_no::text      AS cif_id,
            lf.loan_request_id,
            t4.collateral_id,
            t4.collateral_group,
            t4.collateral_type,
            t4.appraisal_value,
            t4.pledged_amount,
            t4.all_collateral_id
        FROM loan_scope lf
        JOIN (
            SELECT
                b.cif_id::text              AS cif_id,
                x.loan_request_ref          AS loan_request_id,
                y.collateral_group,
                y.collateral_type,
                y.collateral_id,
                case 
			      when mt.is_appraisal = true then z.appraisal_amount   
			      else z.appraisal_value       	
	            end as appraisal_value,
                0::numeric                  AS pledged_amount,
                '' as all_collateral_id
            FROM lps_collateral.trn_request_sheets x
            JOIN lps_collateral.trn_request_sheets_detail y
                 ON y.sheets_id_ref = x.sheets_id
            JOIN lps_collateral.trn_collateral z
                 ON z.collateral_id = y.collateral_id
            LEFT JOIN lps_collateral.trn_contract_owner b
                 ON y.sheets_id_ref::text = b.sheet_id_ref::text
            LEFT JOIN lps_collateral.mas_collateral_matrix mt on mt.collateral_group = z.collateral_group and mt.collateral_type = z.collateral_type 
            		and mt.collateral_subtype = z.collateral_sub_type
            WHERE x.sheets_type          = 'LON'
              AND x.collateral_group NOT IN ('12','13','14','15','20')
              AND (mt.is_appraisal != false
              OR mt.is_guarantor != false)
        ) t4
          ON lf.cif_no          = t4.cif_id
         AND lf.loan_request_id = t4.loan_request_id
    ) n
),
-- select * from new
-- select * from old
-- ========================= รวม old + new และ de-dup =========================
base AS (
    SELECT 
        rn,
        ft,
        cif_id,
        loan_request_id,
        collateral_id,
        collateral_group,
        collateral_type,
        appraisal_value,
        pledged_amount
    FROM (
        SELECT
            ROW_NUMBER() OVER (
                PARTITION BY cif_id, loan_request_id, collateral_id
                ORDER BY rn
            ) AS rowid,
            rn,
            ft,
            cif_id,
            loan_request_id,
            collateral_id,
            collateral_group,
            collateral_type,
            appraisal_value,
            pledged_amount
        FROM old o2
        /* WHERE NOT EXISTS (
            SELECT 1
            FROM new n3
            WHERE n3.cif_id          = o2.cif_id
              AND n3.loan_request_id  = o2.loan_request_id
              AND n3.collateral_id    = o2.collateral_id
              AND n3.collateral_group = o2.collateral_group
        ) */
    ) o
    WHERE o.rowid = 1
    UNION ALL
    SELECT 
        rn,
        ft,
        cif_id,
        loan_request_id,
        collateral_id,
        collateral_group,
        collateral_type,
        appraisal_value,
        pledged_amount
    FROM (
        SELECT
            ROW_NUMBER() OVER (
                PARTITION BY cif_id, loan_request_id, collateral_id
                ORDER BY rn
            ) AS rowid,
            rn,
            ft,
            cif_id,
            loan_request_id,
            collateral_id,
            collateral_group,
            collateral_type,
            appraisal_value,
            pledged_amount
        FROM new n
        WHERE 
        n.collateral_group not IN ('12','13','14','15') AND
        NOT EXISTS (
            SELECT 1
            FROM old o2
            WHERE o2.cif_id          = n.cif_id
              AND o2.collateral_id    = n.collateral_id
              AND o2.collateral_group = n.collateral_group
        )
    ) n2
    WHERE n2.rowid = 1
    UNION ALL
    SELECT 
        rn,
        ft,
        cif_id,
        loan_request_id,
        collateral_id,
        collateral_group,
        collateral_type,
        appraisal_value,
        pledged_amount
    FROM (
        SELECT
            ROW_NUMBER() OVER (
                PARTITION BY cif_id, loan_request_id, collateral_id, collateral_group
                ORDER BY rn
            ) AS rowid,
            rn,
            ft,
            cif_id,
            loan_request_id,
            collateral_id,
            collateral_group,
            collateral_type,
            appraisal_value,
            pledged_amount
        FROM new n
        WHERE 
        n.collateral_group IN ('12','13','14','15') AND
        NOT EXISTS (
            SELECT 1
            FROM old o2
            WHERE o2.cif_id          = n.cif_id
              AND o2.collateral_group = n.collateral_group
              AND o2.all_collateral_id = n.all_collateral_id
        )
    ) n3
    WHERE n3.rowid = 1
),
-- select * from base
-- ========================= col_type =========================
col_type as (
  select distinct *
  from
  (
  select a.cif_id,a.loan_request_id,a.collateral_type
  from old a
  union all
  select b.cif_id,b.loan_request_id,b.collateral_type 
  from new b
  )
  order by collateral_type
)
-- ========================= RESULT =========================


SELECT 
	ls.assessment_no as "เลขที่ใบประเมิน",
    ls.loan_request_id as "เลขที่ใบคำขอ",
    ls.cif_no as "เลขทะเบียนลูกค้า (CIF)",
    case
		WHEN ls.assessment_type = 'CREATE_LOAN' THEN 'ขอสินเชื่อใหม่'
		WHEN ls.assessment_type = 'CHANGE_LOAN' THEN 'ขอสินเชื่อใหม่'
		WHEN ls.assessment_type = 'OVERDRAFT' THEN 'ขอสินเชื่อใหม่'
    	WHEN ls.assessment_type = 'CREATE_DBM' THEN 'รายงานเบิก'
    	WHEN ls.assessment_type = 'CHANGE_DBM' THEN 'รายงานเบิก'
    	WHEN ls.assessment_type = 'CHANGE_DBM' THEN 'รายงานเบิก'
    	WHEN ls.assessment_type = 'REVIEW' THEN 'ทบทวนวงเงินสินเชื่อ'
    else 
        ls.assessment_type
    END AS "ประเภทธุรกรรม",
    ls.report_data -> 'factorCSR' -> 'FC_2' ->> 'data' AS "CUR",
    ls.answer -> 'SUMMARY_CSR' -> 'SSC_2' ->> 'pricing' AS "อัตราดอกเบี้ย",
    to_char(
	  LEAST(
	    1,
	    GREATEST(
	      0,
	      COALESCE(
	        (
	          CASE
	            WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
	            	-- ls.total_dept_dbm
	            	(ls.sum_debt_loan_amount + ls.total_loan_request_amount)
	            ELSE
	              ls.total_dept_dbm
	          END
	        )
	        /
	        NULLIF(
	          (
	            COALESCE(SUM(CASE 
	              WHEN a.collateral_group NOT IN ('12','13','14','15') 
	              THEN COALESCE(a.appraisal_value,0) 
	            END),0)
	            +
	            COALESCE(SUM(CASE 
	              WHEN a.collateral_group IN ('12','13','14','15') 
	              THEN COALESCE(a.pledged_amount,0) 
	            END),0)
	          ),
	        0),
	      0)
	    )
	  )::numeric,
	  'FM999,999,999,990.0000'
	) AS "LTVR",
     case
      WHEN substring(ls.loan_request_id,1,3) <> 'DBM' THEN    
      	-- to_char((ls.total_dept_dbm)::numeric,'FM999,999,999,990.00')
      	to_char((ls.total_dept_dbm + ls.total_loan_request_amount)::numeric,'FM999,999,999,990.00')
      else
        to_char(ls.total_dept_dbm::numeric,'FM999,999,999,990.00')
     end AS "มูลหนี้รวมของ ธ.ก.ส",
    to_char(
			   (coalesce(SUM(CASE WHEN a.collateral_group NOT IN ('12','13','14','15') THEN COALESCE(a.appraisal_value,0) end),0)+
 			   coalesce(SUM(CASE WHEN a.collateral_group IN ('12','13','14','15') THEN COALESCE(a.pledged_amount,0) END),0))
    		 ::numeric,'FM999,999,999,990.00') as "มูลค่าหลักประกัน",
    		 COALESCE((
		SELECT string_agg(collateral_type::text, ',' ORDER BY collateral_type::int) AS collateral_type_list
		FROM col_type c
		where ls.cif_no = c.cif_id 
		and ls.loan_request_id = c.loan_request_id
    ), '-') AS "ประเภทหลักประกัน (กำหนดเป็นรหัส)",
    '1 : อสังหาริมทรัพย์ (ที่ดิน ที่ดินพร้อมสิ่งปลูกสร้าง สิ่งปลูกสร้าง คอนโดมิเนียมห้องชุด)' AS "หลักประกันที่ 1",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '01' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 1",
	'2 : ส.ป.ก. กสน. น.ค' AS "หลักประกันที่ 2",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '02' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 2",
	'3 : สังหาริมทรัพย์พิเศษ (เครื่องจักร)' AS "หลักประกันที่ 3",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '03' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 3",
	'4 : สังหาริมทรัพย์พิเศษ (เรือ)' AS "หลักประกันที่ 4",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '04' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 4",
	'5 : ไม้ยืนต้น' AS "หลักประกันที่ 5",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '05' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 5",
	'6 : สิทธิการเช่า' AS "หลักประกันที่ 6",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '06' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 6",
	'7 : สิทธิการแปลงสินทรัพย์เป็นทุน (หนังสือรับรองเอกสิทธิ ใบอนุญาต สิทธิบัตร อนุสิทธิบัตร และเครื่องหมายการค้า)' AS "หลักประกันที่ 7",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '07' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 7",
	'8 : โอนสิทธิเรียกร้องการรับเงิน' AS "หลักประกันที่ 8",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '08' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 8",
	'9 : รถยนต์/รถจักรยานยนต์' AS "หลักประกันที่ 9",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '09' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 9",
	'10 : จำนำใบหุ้น พันธบัตรรัฐบาล พันธบัตร ธ.ก.ส. และพันธบัตรสถาบันการเงินอื่น' AS "หลักประกันที่ 10",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '10' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 10",
	'11 : สลาก' AS "หลักประกันที่ 11",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '11' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 11",
	'12 : บุคคลค้ำประกัน' AS "หลักประกันที่ 12",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '12' THEN a.pledged_amount  END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 12",
	'13 : บุคคลค้ำประกันแบบรับรองรับผิดอย่างลูกหนี้ร่วมกัน' AS "หลักประกันที่ 13",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '13' THEN a.pledged_amount  END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 13",
	'14 : บุคคลค้ำประกันแบบคณะกรรมการค้ำประกัน' AS "หลักประกันที่ 14",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '14' THEN a.pledged_amount  END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 14",
	'15 : นิติบุคคลค้ำประกัน' AS "หลักประกันที่ 15",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '15' THEN a.pledged_amount  END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 15",
	'16 : การจำนำผลิตผลและจำนำประทวน' AS "หลักประกันที่ 16",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '16' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 16",
	'17 : หนังสือค้ำประกันบรรษัทประกันสินเชื่ออุตสาหกรรมขนาดย่อย (บสย.)' AS "หลักประกันที่ 17",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '17' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 17",
	'18 : หนังสือรับรองสิทธิ (บำเหน็จตกทอด)' AS "หลักประกันที่ 18",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '18' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 18",
	'19 : หนังสือค้ำประกัน (อื่นๆ)' AS "หลักประกันที่ 19",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '19' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 19",
	'20 : เงินฝากค้ำประกัน' AS "หลักประกันที่ 20",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '20' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 20",
	'21 : สินค้าคงคลัง (Packing Stock)' AS "หลักประกันที่ 21",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '21' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 21",
	'22 : ตั๋วเงิน (ตั๋วสัญญาใช้เงิน ตั๋วแลกเงิน เช็ค)' AS "หลักประกันที่ 22",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '22' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 22",
	'23 : หลักประกันอื่นนอกเหนือจาก 1-22' AS "หลักประกันที่ 23",
    COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '23' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 23"
FROM loan_scope ls 
left outer JOIN base a  ON a.loan_request_id = ls.loan_request_id
GROUP BY
    ls.cif_no,
    ls.loan_request_id,
    ls.assessment_no,
    ls.assessment_type,
    ls.total_dept_dbm,
    ls.total_loan_request_amount,
    ls.sum_debt_loan_amount,
    ls.report_data,
    ls.answer
ORDER BY ls.cif_no, ls.loan_request_id;