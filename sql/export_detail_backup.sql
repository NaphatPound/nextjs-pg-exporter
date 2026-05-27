-- sql/export_detail.sql
-- Parameters: $1 = from (timestamp), $2 = to (timestamp), $3 = assessment_no
WITH
          base AS (
            SELECT d.application_id, d.answer, d.report_data, d.results_score,
            d.data->'mapping'->>'formula_code' as formula_code,
            d.assessment_no
            --FROM lps_corporate_loan.trn_corp_assessment_answer d
            from cif.mas_assessment_answer d
            WHERE d.approved_date BETWEEN $1::timestamp AND ($2::timestamp + interval '1 millisecond')
	      AND d.is_export_csv = true
--	      and d.cust_desc = 'Agri'
	      and d.assessment_no = $3
          ),
          /* ===================== Variables (VC_xxx) ===================== */
          coeff_node AS (
            SELECT COALESCE(results_score #> '{CSR,coefficientVariable}', results_score->'coefficientVariable') AS node
            FROM base
          ),
          codes AS (
            SELECT k AS code
            FROM coeff_node, LATERAL jsonb_object_keys(node) AS k
            WHERE jsonb_typeof(node) = 'object'
            UNION
            SELECT x->>'variable_code' AS code
            FROM coeff_node, LATERAL jsonb_array_elements(node) AS x
            WHERE jsonb_typeof(node) = 'array'
            UNION
            SELECT k AS code
            FROM base, LATERAL jsonb_object_keys(report_data->'variable') AS k
          ),
          xval AS (
            SELECT
              c.code,
              COALESCE(
                NULLIF(base.answer->'coefficientVariable'->>c.code, '')::numeric,
                NULLIF((base.report_data->'variable'->c.code->>'data'),'')::numeric
              ) AS x_value
            FROM base, codes c
          ),
          meta_var_full AS (
            -- node เป็น object
            SELECT
              c.code,
              (node->c.code)->>'description' AS description_meta,
              CASE WHEN ((node->c.code)->>'X_Parameter') ~ '^[+-]?\d+$'
                   THEN ((node->c.code)->>'X_Parameter')::int ELSE 0 END AS idx0,
              CASE
                WHEN jsonb_typeof((node->c.code)->'coefficientValue') = 'array' THEN
                  COALESCE(
                    (
                      SELECT NULLIF(e.val #>> '{}','')::numeric
                      FROM jsonb_array_elements((node->c.code)->'coefficientValue') WITH ORDINALITY AS e(val, ord)
                      WHERE (ord - 1) = GREATEST(
                                           CASE WHEN ((node->c.code)->>'X_Parameter') ~ '^[+-]?\d+$'
                                                THEN ((node->c.code)->>'X_Parameter')::int ELSE 0 END, 0)
                      LIMIT 1
                    ),
                    NULLIF(((node->c.code)->'coefficientValue'->>0),'')::numeric
                  )
                ELSE
                  NULLIF((node->c.code)->>'coefficientValue','')::numeric
              END AS coefficientValue,
              NULLIF((node->c.code)->>'X_Parameter','')::numeric AS X_Parameter,
              (node->c.code)->>'X_Parameter_varchar'             AS X_Parameter_varchar
            FROM coeff_node, codes c
            WHERE jsonb_typeof(node) = 'object'
            UNION ALL
            -- node เป็น array
            SELECT
              x->>'variable_code'          AS code,
              x->>'description'            AS description_meta,
              CASE WHEN (x->>'X_Parameter') ~ '^[+-]?\d+$'
                   THEN (x->>'X_Parameter')::int ELSE 0 END AS idx0,
              CASE
                WHEN jsonb_typeof(x->'coefficientValue') = 'array' THEN
                  COALESCE(
                    (
                      SELECT NULLIF(e.val #>> '{}','')::numeric
                      FROM jsonb_array_elements(x->'coefficientValue') WITH ORDINALITY AS e(val, ord)
                      WHERE (ord - 1) = GREATEST(
                                           CASE WHEN (x->>'X_Parameter') ~ '^[+-]?\d+$'
                                                THEN (x->>'X_Parameter')::int ELSE 0 END, 0)
                      LIMIT 1
                    ),
                    NULLIF((x->'coefficientValue'->>0),'')::numeric
                  )
                ELSE
                  NULLIF(x->>'coefficientValue','')::numeric
              END AS coefficientValue,
              NULLIF(x->>'X_Parameter','')::numeric AS X_Parameter,
              x->>'X_Parameter_varchar'             AS X_Parameter_varchar
            FROM coeff_node
            CROSS JOIN LATERAL jsonb_array_elements(node) x
            WHERE jsonb_typeof(node) = 'array'
          ),
          meta_var_idx AS (
            SELECT code, idx0, X_Parameter_varchar AS xparam_varchar
            FROM meta_var_full
          ),
          var_name AS (
            SELECT
              c.code,
              (base.report_data->'variable'->c.code->>'name') AS thai_name
            FROM base, codes c
          ),
          factor_node AS (
            SELECT COALESCE(results_score #> '{CSR,factorCSR}', results_score->'factorCSR') AS node, formula_code,assessment_no
            FROM base
          ),
          factor_rs AS (
            -- node เป็น array
            SELECT
              x->>'factor_code' AS factor_code,
              x->>'factor_name' AS factor_name,
              x->>'description' AS description_rs,
              x->>'variable'    AS xvar,
              CASE jsonb_typeof(x->'coefficient')
                WHEN 'array'  THEN x->'coefficient'
                WHEN 'null'   THEN '[]'::jsonb
                ELSE jsonb_build_array(x->'coefficient')
              END AS coeff_arr_norm,
              CASE jsonb_typeof(x->'variable_code')
                WHEN 'array'  THEN (SELECT array_agg(e) FROM jsonb_array_elements_text(x->'variable_code') e)
                WHEN 'string' THEN ARRAY[ x->>'variable_code' ]
                ELSE ARRAY[]::text[]
              END AS var_codes,
              formula_code,
              assessment_no
            FROM factor_node
            CROSS JOIN LATERAL jsonb_array_elements(node) x
            WHERE jsonb_typeof(node) = 'array'
            UNION ALL
            -- node เป็น object
            SELECT
              k                  AS factor_code,
              v->>'factor_name'  AS factor_name,
              v->>'description'  AS description_rs,
              v->>'variable'     AS xvar,
              CASE jsonb_typeof(v->'coefficient')
                WHEN 'array'  THEN v->'coefficient'
                WHEN 'null'   THEN '[]'::jsonb
                ELSE jsonb_build_array(v->'coefficient')
              END AS coeff_arr_norm,
              CASE jsonb_typeof(v->'variable_code')
                WHEN 'array'  THEN (SELECT array_agg(e) FROM jsonb_array_elements_text(v->'variable_code') e)
                WHEN 'string' THEN ARRAY[ v->>'variable_code' ]
                ELSE ARRAY[]::text[]
              END AS var_codes,
              formula_code,
              assessment_no
            FROM factor_node
            CROSS JOIN LATERAL jsonb_each(node) AS t(k, v)
            WHERE jsonb_typeof(node) = 'object'
          ),
          factor_rd AS (
            SELECT
              k AS factor_code,
              NULLIF((base.report_data->'factorCSR'->k->>'data'),'')::numeric AS data_rd,
              (base.report_data->'factorCSR'->k->>'name')                     AS name_rd,
              base.formula_code,
              base.assessment_no
            FROM base, LATERAL jsonb_object_keys(base.report_data->'factorCSR') AS k
          ),
          coeff_pick AS (
            SELECT
              frs.factor_code,
              frs.factor_name,
              frs.description_rs,
              frs.xvar,
              frs.coeff_arr_norm,
              frd.data_rd,
              frd.formula_code,
              frd.assessment_no,
              CASE
                WHEN frd.data_rd IS NOT NULL
                     AND frd.data_rd::text ~ '^[+-]?\d+$'
                     AND frd.data_rd::int BETWEEN 0 AND GREATEST(jsonb_array_length(frs.coeff_arr_norm) - 1, 0)
                THEN frd.data_rd::int
                ELSE COALESCE(
                       (SELECT mv.idx0 FROM meta_var_idx mv WHERE mv.code = ANY (frs.var_codes)             LIMIT 1),
                       (SELECT mv.idx0 FROM meta_var_idx mv WHERE mv.xparam_varchar = frs.xvar             LIMIT 1),
                       0
                     )
              END AS idx0_choose
            FROM factor_rs frs
            LEFT JOIN factor_rd frd ON frd.factor_code = frs.factor_code
          ),
	factor_join AS (
		SELECT
		COALESCE(frd.name_rd, frs.factor_name) AS factor_display_name,
		frs.description_rs,
		frs.xvar,
		frd.data_rd                             AS x_value_rd,
		COALESCE(jsonb_array_length(frs.coeff_arr_norm), 0) AS coeff_count,
		COALESCE(
			(
			SELECT NULLIF(e.val #>> '{}','')::numeric
			FROM jsonb_array_elements(frs.coeff_arr_norm) WITH ORDINALITY AS e(val, ord)
			WHERE (ord - 1) = cp.idx0_choose
			LIMIT 1
			),
			NULLIF((frs.coeff_arr_norm->>0),'')::numeric
		) AS coeff_first,
		frd.formula_code,
		frd.assessment_no
		FROM coeff_pick cp
		JOIN factor_rs frs  ON frs.factor_code = cp.factor_code
		LEFT JOIN factor_rd frd ON frd.factor_code = cp.factor_code
	),
    frm_code as (
	        SELECT
	          coefficientvariable,
			  x_value,
			  coefficientvalue,
			  x_parameter,
			  description,
			  x_parameter_varchar,
			  formula_code,
			  assessment_no
	        FROM (
	    -- Factors
	    SELECT
	      2 AS dataseq,
	      fj.factor_display_name                             AS coefficientVariable,
	      (
	      CASE
	        WHEN fj.coeff_count > 1 THEN
	        ROUND( COALESCE(1 * fj.coeff_first, 0), 4 )::numeric(38,4)
	        when fj.x_value_rd is null then 
	        ROUND(COALESCE(fj.coeff_first, 0), 4)::numeric(38,4)
	        Else 
	        ROUND( COALESCE(fj.x_value_rd, 0) * COALESCE(fj.coeff_first, 0), 4 )::numeric(38,4)
	        END
	        )                                                  AS X_Value,
	  ROUND(COALESCE(fj.coeff_first, 0), 4)::numeric(38,4) AS coefficientValue,									    
	    ROUND(COALESCE(fj.x_value_rd, 0), 4)::numeric(38,4)  AS X_Parameter,
	    fj.description_rs                                  AS description,
	    fj.xvar                                            AS X_Parameter_varchar,
	    fj.formula_code,
	    fj.assessment_no
	    FROM factor_join fj     
	    where fj.factor_display_name <> 'LTVR'
	        ) a
	        ORDER BY a.dataseq, a.description
	),
	ltvr_code as (
WITH loan_scope AS ( 
    SELECT DISTINCT
        maa.cif_no,
        maa.application_id  as  loan_request_id,   
        coalesce(s.sum_debt_loan_amount::numeric,0) as sum_debt_loan_amount,
		coalesce((maa.report_data->'variable'->'VC_243'->> 'data')::numeric,0) as total_dept_dbm,
        maa.assessment_no,
        maa.assessment_type,
        maa.data->'mapping'->>'formula_code' as formula_code
    FROM cif.mas_assessment_answer maa
    left outer JOIN lps_corporate_loan.trn_loan_sll_detail s
      ON maa.cif_no = s.cif_no
      and maa.application_id  = s.loan_request_id 
    WHERE maa.approved_date BETWEEN $1::timestamp AND ($2::timestamp + interval '1 millisecond')
      AND maa.is_export_csv = true
      AND maa.assessment_no = $3
      -- and maa.cust_desc = 'Agri'
      -- and maa.application_id = 'DBM2512120000012'
),
-- select * from new
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
        o.create_datetime
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
            t1.create_datetime
        FROM loan_scope lf
        JOIN (
            select
            	ROW_NUMBER() OVER (
                    PARTITION BY b.cif_id::text, c.collateral_group, c.contract_id
                ) AS rowid,
                b.cif_id::text    AS cif_id,
                d.collateral_id,
                c.collateral_group,
                c.collateral_type,
                a.create_datetime,
                d.appraisal_value,
                a.pledged_amount
            FROM lps_collateral.trn_contract a
            LEFT JOIN lps_collateral.trn_contract_owner b
                   ON a.contract_no::text = b.contract_no::text
            LEFT JOIN lps_collateral.trn_collateral_contract c
                   ON c.contract_no = b.contract_no
            LEFT JOIN lps_collateral.trn_collateral d
                   ON d.collateral_no = c.collateral_no
            WHERE c.collateral_group IN ('12','13','14','15') 
            and a.contract_status = '0'
        ) t1
          ON lf.cif_no = t1.cif_id
          WHERE t1.rowid = 1
          AND t1.create_datetime <= (SELECT MAX(update_datetime) + interval '1 millisecond' + interval '7 hour' FROM cif.mas_assessment_answer WHERE assessment_no = lf.assessment_no)
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
            t1.create_datetime
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
                f.is_appraisal as isAPP
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
          AND t1.create_datetime <= (SELECT MAX(update_datetime) + interval '1 millisecond' + interval '7 hour' FROM cif.mas_assessment_answer WHERE assessment_no = lf.assessment_no)
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
        n.pledged_amount
    FROM (
        -- กลุ่ม 12–15 ใช้ obligation_value เป็น pledged_amount
        SELECT
            lf.cif_no::text      AS cif_id,
            lf.loan_request_id,
            t3.collateral_id,
            t3.collateral_group,
            t3.collateral_type,
            t3.appraisal_value,
            t3.pledged_amount
        FROM loan_scope lf
        JOIN (
            SELECT
                ROW_NUMBER() OVER (
                    PARTITION BY b.cif_id::text, x.loan_request_ref, y.sheets_id_ref
                    ORDER BY y.obligation_value
                ) AS rowid,
                b.cif_id::text              AS cif_id,
                x.loan_request_ref          AS loan_request_id,
                y.collateral_group,
                y.collateral_type,
                y.collateral_id,
                0::numeric                  AS appraisal_value,
                y.obligation_value::numeric AS pledged_amount
            FROM lps_collateral.trn_request_sheets x
            JOIN lps_collateral.trn_request_sheets_detail y
                 ON y.sheets_id_ref = x.sheets_id
            JOIN lps_collateral.trn_collateral z
                 ON z.collateral_id = y.collateral_id
            LEFT JOIN lps_collateral.trn_contract_owner b
                 ON y.sheets_id_ref::text = b.sheet_id_ref::text
            WHERE x.sheets_type      = 'LON'
              AND x.collateral_group IN ('12','13','14','15')
        ) t3
          ON lf.cif_no          = t3.cif_id
         AND lf.loan_request_id = t3.loan_request_id
        WHERE t3.rowid = 1
        UNION all
        -- กลุ่มเงินฝากคำ้ใช้ available_value
        SELECT
            lf.cif_no::text      AS cif_id,
            lf.loan_request_id,
            t5.collateral_id,
            t5.collateral_group,
            t5.collateral_type,
            t5.appraisal_value,
            t5.pledged_amount
        FROM loan_scope lf
        JOIN (
            SELECT
                b.cif_id::text              AS cif_id,
                x.loan_request_ref          AS loan_request_id,
                y.collateral_group,
                y.collateral_type,
                y.collateral_id,
                (det_elem->>'availableValue')::numeric AS appraisal_value,
                0::numeric                  AS pledged_amount
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
        -- กลุ่มอื่น ๆ ใช้ appraisal_value
        SELECT
            lf.cif_no::text      AS cif_id,
            lf.loan_request_id,
            t4.collateral_id,
            t4.collateral_group,
            t4.collateral_type,
            t4.appraisal_value,
            t4.pledged_amount
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
                0::numeric                  AS pledged_amount
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
        ) t4
          ON lf.cif_no          = t4.cif_id
         AND lf.loan_request_id = t4.loan_request_id
    ) n
),
-- select * from new
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
        FROM old
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
        WHERE NOT EXISTS (
            SELECT 1
            FROM old o2
            WHERE o2.cif_id          = n.cif_id
              AND o2.loan_request_id  = n.loan_request_id
              AND o2.collateral_id    = n.collateral_id
              AND o2.collateral_group = n.collateral_group
        )
    ) n2
    WHERE n2.rowid = 1
),
-- select * from base
-- ========================= SUMDEPT ต่อ (cif, loan_request_id) =========================
sumdept AS (
    WITH raw AS (
        SELECT
            ls.cif_no,
            ls.loan_request_id,
            coalesce(ls.sum_debt_loan_amount,0) as sum_debt_loan_amount,
            to_jsonb(t.*) AS row_json
        FROM loan_scope ls
        CROSS JOIN LATERAL lps_corporate_loan.fn_get_loan_cap_information(
            substring(ls.loan_request_id,1,3),
            ls.loan_request_id,
            NULL
        ) t
    ),
    json_array AS (
        SELECT
            cif_no,
            loan_request_id,
            sum_debt_loan_amount,
            row_json -> 'json_field' AS array_json
        FROM raw
    ),
    loan AS (
        SELECT
            cif_no,
            loan_request_id,
            sum_debt_loan_amount,
            jsonb_array_elements(
                CASE 
                    WHEN jsonb_typeof(array_json) = 'array' 
                    THEN array_json 
                    ELSE '[]'::jsonb 
                END
            ) AS item
        FROM json_array
    )
    SELECT 
        cif_no,
        loan_request_id,
        coalesce(MAX(sum_debt_loan_amount)::numeric,0) AS sum_debt_loan_amount,
        coalesce(SUM(
            CASE
                WHEN item->>'status' = 'APPROVE' THEN
                    COALESCE((item->'loan_approval_information'->>'approveAmount')::numeric, 0)
                WHEN (
                    jsonb_array_length(
                        CASE 
                            WHEN jsonb_typeof(item->'loan_purpose') = 'array' 
                            THEN item->'loan_purpose' 
                            ELSE '[]'::jsonb 
                        END
                    ) > 0
                    AND NOT EXISTS (
                        SELECT 1
                        FROM jsonb_array_elements(
                            CASE 
                                WHEN jsonb_typeof(item->'loan_purpose') = 'array' 
                                THEN item->'loan_purpose' 
                                ELSE '[]'::jsonb 
                            END
                        ) elem
                        WHERE (elem->>'potentialLoanAmount') IS NULL
                           OR elem->>'potentialLoanAmount' = ''
                    )
                ) THEN (
                    SELECT coalesce(SUM((elem->>'potentialLoanAmount')::numeric),0)
                    FROM jsonb_array_elements(
                        CASE 
                            WHEN jsonb_typeof(item->'loan_purpose') = 'array' 
                            THEN item->'loan_purpose' 
                            ELSE '[]'::jsonb 
                        END
                    ) elem
                )
                WHEN substring(loan_request_id,1,3) = 'CPL' THEN
                    COALESCE((item->>'loan_credit_equivalent_amount')::numeric, 0)
                ELSE
                    COALESCE((item->>'loan_amount')::numeric, 0)
            END
        )::numeric,0) +  coalesce(MAX(sum_debt_loan_amount)::numeric,0) AS total_dept
    FROM loan
    WHERE item->>'cif_no' = cif_no   
    GROUP BY cif_no, loan_request_id
),
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
    case
      WHEN substring(ls.loan_request_id,1,3) <> 'DBM' THEN    
	    to_char(coalesce(b.total_dept    
	    /
	    NULLIF((
				   (coalesce(SUM(CASE WHEN a.collateral_group NOT IN ('12','13','14','15') THEN COALESCE(a.appraisal_value,0) end),0)+
	 			   coalesce(SUM(CASE WHEN a.collateral_group IN ('12','13','14','15') THEN COALESCE(a.pledged_amount,0) END),0))
	    ),0),0)::numeric,'FM999,999,999,990.0000')
      else
        to_char(coalesce(ls.total_dept_dbm
        	    /
	    NULLIF((
				   (coalesce(SUM(CASE WHEN a.collateral_group NOT IN ('12','13','14','15') THEN COALESCE(a.appraisal_value,0) end),0)+
	 			   coalesce(SUM(CASE WHEN a.collateral_group IN ('12','13','14','15') THEN COALESCE(a.pledged_amount,0) END),0))
	    ),0),0)::numeric,'FM999,999,999,990.0000')
     end AS "LTVR",
     case
      WHEN substring(ls.loan_request_id,1,3) <> 'DBM' THEN    
        to_char(b.total_dept::numeric,'FM999,999,999,990.00') 
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
left join sumdept b on ls.cif_no = b.cif_no AND ls.loan_request_id = b.loan_request_id
GROUP BY ls.cif_no, ls.loan_request_id,ls.assessment_no,ls.assessment_type,ls.total_dept_dbm,b.total_dept
ORDER BY ls.cif_no, ls.loan_request_id	
	),
x_value as (
		select					
			CASE
			  WHEN SUM(out.x_value) >= 0 THEN
			    1 / (1 + exp(-LEAST(SUM(out.x_value), 50)))
			  ELSE
			    exp(GREATEST(SUM(out.x_value), -50))
			      / (1 + exp(GREATEST(SUM(out.x_value), -50)))
			END AS PD,
			out.assessment_no,
			out.formula_code
		FROM (
    select frm.assessment_no,x_value::numeric,frm.formula_code from frm_code frm  
     join base b on frm.assessment_no = b.assessment_no
    union
    select  "เลขที่ใบประเมิน" ,"LTVR"::numeric , formula_code from  ltvr_code lv    
    join base b on lv."เลขที่ใบประเมิน" = b.assessment_no
    ) out
    group by out.assessment_no ,formula_code
),	
	csr_criteria AS (
		select * from lps_corporate_loan.mas_corp_assessment_csr_criteria
	),
	calc_value as (
	select *
	from csr_criteria csr 
	join x_value frm on frm.formula_code = csr.formula_code
	where frm.PD >= csr.minimum_pd and frm.PD < csr.maximum_pd	
	)
        /* ===================== Output ===================== */	
    select * from ltvr_code	ltv
    join calc_value cal on cal.assessment_no = ltv."เลขที่ใบประเมิน"

