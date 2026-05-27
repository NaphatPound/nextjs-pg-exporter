-- sql/export_detail.sql
-- Parameters: $1 = from (timestamp), $2 = to (timestamp), $3 = assessment_no, $4 = assessment_type
WITH
    base AS (
      SELECT d.application_id, d.answer, d.report_data, d.results_score,
      d.data->'mapping'->>'formula_code' as formula_code,
      d.assessment_no
      --FROM lps_corporate_loan.trn_corp_assessment_answer d
      from cif.mas_assessment_answer d
      WHERE d.approved_date BETWEEN $1::timestamp AND ($2::timestamp + interval '1 millisecond')
	AND d.is_export_csv = true
	AND d.assessment_no = $3
	AND d.cust_desc = $4
    ),
    -- select * from base
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
                coalesce(cl.total_loan_request_amount::numeric,rt.total_loan_request_amount::numeric) as total_loan_request_amount,
                coalesce((maa.report_data->'variable'->'VC_243'->> 'data')::numeric,0) as total_dept_dbm,
                maa.data -> 'mapping' ->> 'formula_code' as formula_code,
                maa.assessment_no,
                maa.assessment_type,
                maa.integrate_data,
                maa.answer,
                maa.report_data,
                maa.cust_type,
                COALESCE(NULLIF(obj1.obj ->> 'businessType1',''), NULLIF(obj2.obj ->> 'businessType1','')) AS businessType1,
                COALESCE(NULLIF(obj1.obj ->> 'businessType2',''), NULLIF(obj2.obj ->> 'businessType2','')) AS businessType2,
                COALESCE(NULLIF(obj1.obj ->> 'businessType3',''), NULLIF(obj2.obj ->> 'businessType3','')) AS businessType3,
                COALESCE(NULLIF(obj1.obj ->> 'businessType1Desc',''), NULLIF(obj2.obj ->> 'businessType1Desc','')) AS businessType1Desc,
                COALESCE(NULLIF(obj1.obj ->> 'businessType2Desc',''), NULLIF(obj2.obj ->> 'businessType2Desc','')) AS businessType2Desc,
                COALESCE(NULLIF(obj1.obj ->> 'businessType3Desc',''), NULLIF(obj2.obj ->> 'businessType3Desc','')) AS businessType3Desc,
                COALESCE(NULLIF(obj1.obj ->> 'mainProductType',''), NULLIF(obj2.obj ->> 'mainProductType','')) AS mainProductType,
                COALESCE(NULLIF(obj1.obj ->> 'mainProductTypeDesc',''), NULLIF(obj2.obj ->> 'mainProductTypeDesc','')) AS mainProductTypeDesc,
                COALESCE(NULLIF(obj1.obj ->> 'productTypeObjective',''), NULLIF(obj2.obj ->> 'productTypeObjective','')) AS productTypeObjective,
                COALESCE(NULLIF(obj1.obj ->> 'productTypeObjectiveDesc',''), NULLIF(obj2.obj ->> 'productTypeObjectiveDesc','')) AS productTypeObjectiveDesc
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

            left outer JOIN disbursement.trn_disbursement c on c.disburse_no = maa.application_id
            LEFT JOIN LATERAL (
                    SELECT obj
                    FROM jsonb_array_elements(c.objectives) AS obj
                    WHERE obj ->> 'businessType1' = maa.integrate_data -> 'isicCode' ->> 'isicLevel1'
                        AND obj ->> 'businessType2' = maa.integrate_data -> 'isicCode' ->> 'isicLevel2'
                        AND obj ->> 'businessType3' = maa.integrate_data -> 'isicCode' ->> 'isicLevel3'
                        AND obj ->> 'mainProductType' = maa.integrate_data -> 'isicCode' ->> 'isicLevel4'
                        AND obj ->> 'productTypeObjective' = maa.integrate_data -> 'isicCode' ->> 'isicLevel5'
                    LIMIT 1
            ) obj1 ON TRUE

            left outer JOIN disbursement.trn_corp_disbursement cc on cc.disburse_no = maa.application_id
            LEFT JOIN LATERAL (
                    SELECT obj
                    FROM jsonb_array_elements(cc.objectives) AS obj
                    WHERE obj ->> 'businessType1' = maa.integrate_data -> 'isicCode' ->> 'isicLevel1'
                        AND obj ->> 'businessType2' = maa.integrate_data -> 'isicCode' ->> 'isicLevel2'
                        AND obj ->> 'businessType3' = maa.integrate_data -> 'isicCode' ->> 'isicLevel3'
                        AND obj ->> 'mainProductType' = maa.integrate_data -> 'isicCode' ->> 'isicLevel4'
                        AND obj ->> 'productTypeObjective' = maa.integrate_data -> 'isicCode' ->> 'isicLevel5'
                    LIMIT 1
            ) obj2 ON TRUE

            WHERE maa.approved_date BETWEEN $1::timestamp AND ($2::timestamp + interval '1 millisecond')
            AND maa.is_export_csv = true
            AND maa.assessment_no = $3
            AND maa.cust_desc = $4
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
                        /* ROW_NUMBER() OVER (
                            PARTITION BY b.cif_id::text, c.collateral_group, c.contract_id
                        ) AS rowid, */
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
                        /* ROW_NUMBER() OVER (
                            PARTITION BY b.cif_id::text, x.loan_request_ref, y.sheets_id_ref
                            ORDER BY y.obligation_value
                        ) AS rowid, */
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
                -- WHERE t3.rowid = 1
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
                        (det_elem->>'availableValue')::numeric AS appraisal_value,
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
                ) t4
                ON lf.cif_no          = t4.cif_id
                AND lf.loan_request_id = t4.loan_request_id
            ) n
        ),
        -- select * from new where all_collateral_id = '2023931166-2023946027'
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
        base_new AS (
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
            ls.formula_code as "สูตรการประเมิน",
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
            to_char(
            LEAST(
                1,
                GREATEST(
                0,
                COALESCE(
                    (
                    CASE
                        WHEN substring(ls.loan_request_id,1,3) <> 'DBM' THEN
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
            WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
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
            COALESCE(to_char(SUM(CASE WHEN a.collateral_group = '23' THEN a.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกันที่ 23",

            -- address
            COALESCE((ls.integrate_data -> 'cifData' -> 'generalData' -> 'addressInfo' ->> 'addrRegisteredSubDistrictCode')::text, '-') AS "SubDistrictCode",
            COALESCE((ls.integrate_data -> 'cifData' -> 'generalData' -> 'addressInfo' ->> 'addrRegisteredSubDistrictCodeDesc')::text, '-') AS "SubDistrictCode",
            COALESCE((ls.integrate_data -> 'cifData' -> 'generalData' -> 'addressInfo' ->> 'addrRegisteredDistrictCode')::text, '-') AS "DistrictCode",
            COALESCE((ls.integrate_data -> 'cifData' -> 'generalData' -> 'addressInfo' ->> 'addrRegisteredDistrictCodeDesc')::text, '-') AS "DistrictCodeDesc",
            COALESCE((ls.integrate_data -> 'cifData' -> 'generalData' -> 'addressInfo' ->> 'addrRegisteredProvinceCode')::text, '-') AS "ProvinceCode",
            COALESCE((ls.integrate_data -> 'cifData' -> 'generalData' -> 'addressInfo' ->> 'addrRegisteredProvinceCodeDesc')::text, '-') AS "ProvinceCodeDesc",

            -- isic code
            -- isic code level 1
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel1')::text, '-')
            else
                COALESCE(ls.businessType1::text, '-')
            end AS "isic_code_level1",
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel1Desc')::text, '-')
            else
                COALESCE(ls.businessType1Desc::text, '-')
            end AS "isic_code_desc_level1",
            -- isic code level 2
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel2')::text, '-')
            else
                COALESCE(ls.businessType2::text, '-')
            end AS "isic_code_level2",
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel2Desc')::text, '-')
            else
                COALESCE(ls.businessType2Desc::text, '-')
            end AS "isic_code_desc_level2",
            -- isic code level 3
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel3')::text, '-')
            else
                COALESCE(ls.businessType3::text, '-')
            end AS "isic_code_level3",
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel3Desc')::text, '-')
            else
                COALESCE(ls.businessType3Desc::text, '-')
            end AS "isic_code_desc_level3",
            -- isic code level 4
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel4')::text, '-')
            else
                COALESCE(ls.mainProductType::text, '-')
            end AS "isic_code_level4",
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel4Desc')::text, '-')
            else
                COALESCE(ls.mainProductTypeDesc::text, '-')
            end AS "isic_code_desc_level4",
            -- isic code level 5
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel5')::text, '-')
            else
                COALESCE(ls.productTypeObjective::text, '-')
            end AS "isic_code_level5",
            CASE WHEN substring(ls.loan_request_id,1,3) <> 'DBM' then
                COALESCE((ls.integrate_data -> 'isicCode' ->> 'isicLevel5Desc')::text, '-')
            else
                COALESCE(ls.productTypeObjectiveDesc::text, '-')
            end AS "isic_code_desc_level5",
            
            -- group general
            -- variable
            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_176' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-') AS "รายได้ในภาคการเกษตร",
            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_177' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-') AS "รายได้นอกภาคการเกษตร",
            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_178' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-') AS "รายได้อื่น",
            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_179' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-') AS "รายจ่ายในภาคการเกษตร",
            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_180' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-') AS "รายจ่ายนอกภาคการเกษตร",
            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_181' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-') AS "ค่าใช้จ่ายในครัวเรือน",
            COALESCE((ls.report_data -> 'variable' -> 'VC_182' ->> 'data')::text, '-') AS "การมี/ไม่มีเงินฝากออมทรัพย์กับ ธ.ก.ส.",
            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-') AS "จำนวนเงินฝากออมทรัพย์กับ ธ.ก.ส.",
            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_243' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-') AS "มูลหนี้รวมของ ธ.ก.ส",
            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_244' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-') AS "มูลค่าหลักประกัน",
            -- factor CSR
            CASE WHEN ls.formula_code IN ('FMC_1', 'FMC_2', 'FMC_11', 'FMC_12') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_2' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_3', 'FMC_4', 'FMC_13', 'FMC_14') then
                    '-'
                WHEN ls.formula_code IN ('FMC_5', 'FMC_6', 'FMC_15', 'FMC_16') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_2' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_7', 'FMC_8', 'FMC_17', 'FMC_18') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_2' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_9', 'FMC_10', 'FMC_19', 'FMC_20') then
                    '-'
            else
                '-'
            end AS "Age",

            CASE WHEN ls.formula_code IN ('FMC_1', 'FMC_2', 'FMC_11', 'FMC_12') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_7' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_3', 'FMC_4', 'FMC_13', 'FMC_14') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_3' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_5', 'FMC_6', 'FMC_15', 'FMC_16') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_2' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_7', 'FMC_17') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_3' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_9', 'FMC_10', 'FMC_19', 'FMC_20') then
                    '-'
            else
                '-'
            end AS "DSR",

            CASE WHEN ls.formula_code IN ('FMC_1', 'FMC_2', 'FMC_11', 'FMC_12') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_3' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_3', 'FMC_4', 'FMC_13', 'FMC_14') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_2' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_5', 'FMC_6', 'FMC_15', 'FMC_16') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_7' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_8', 'FMC_18') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_10' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_9', 'FMC_10', 'FMC_19', 'FMC_20') then
                    '-'
            else
                '-'
            end AS "IncE",

            CASE WHEN ls.formula_code IN ('FMC_1', 'FMC_2', 'FMC_11', 'FMC_12') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_4' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_3', 'FMC_4', 'FMC_13', 'FMC_14') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_5' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_5', 'FMC_6', 'FMC_15', 'FMC_16') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_8' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_7', 'FMC_17') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_5' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_8', 'FMC_18') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_8' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_9', 'FMC_10', 'FMC_19', 'FMC_20') then
                    '-'
            else
                '-'
            end AS "LTVR_factor",

            CASE WHEN ls.formula_code IN ('FMC_1', 'FMC_2', 'FMC_11', 'FMC_12') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_5' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_2', 'FMC_4', 'FMC_13', 'FMC_14') then
                    '-'
                WHEN ls.formula_code IN ('FMC_5', 'FMC_6', 'FMC_15', 'FMC_16') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_4' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_7', 'FMC_8', 'FMC_17', 'FMC_18') then
                    COALESCE((ls.report_data -> 'factorCSR' -> 'FC_6' ->> 'data')::text, '-')
                WHEN ls.formula_code IN ('FMC_9', 'FMC_10', 'FMC_19', 'FMC_20') then
                    '-'
            else
                '-'
            end AS "Saving_C",

            CASE WHEN ls.formula_code IN ('FMC_1', 'FMC_2', 'FMC_11', 'FMC_12') then
                    CASE WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_5' ->> 'data', ''), '0')::numeric = 0 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric BETWEEN 0 AND 5000.99
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '5,000.00' END
                        WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_5' ->> 'data', ''), '0')::numeric = 1 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric BETWEEN 5001 AND 10000.99
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '10,000.99' END
                        WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_5' ->> 'data', ''), '0')::numeric = 2 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric BETWEEN 10001 AND 20000.99
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '20,000.99' END
                        WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_5' ->> 'data', ''), '0')::numeric = 3 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric > 20001
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '20,001.00' END
                        ELSE
                            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                        END
                WHEN ls.formula_code IN ('FMC_3', 'FMC_4', 'FMC_13', 'FMC_14') then
                    '-'
                WHEN ls.formula_code IN ('FMC_5', 'FMC_6', 'FMC_15', 'FMC_16') then
                    CASE WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_4' ->> 'data', ''), '0')::numeric = 0 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric BETWEEN 0 AND 5000.99
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '5,000.00' END
                        WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_4' ->> 'data', ''), '0')::numeric = 1 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric BETWEEN 5001 AND 10000.99
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '10,000.99' END
                        WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_4' ->> 'data', ''), '0')::numeric = 2 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric BETWEEN 10001 AND 20000.99
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '20,000.99' END
                        WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_4' ->> 'data', ''), '0')::numeric = 3 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric > 20001
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '20,001.00' END
                        ELSE
                            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                        END
                WHEN ls.formula_code IN ('FMC_7', 'FMC_8', 'FMC_17', 'FMC_18') then
                    CASE WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_6' ->> 'data', ''), '0')::numeric = 0 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric BETWEEN 0 AND 5000.99
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '5,000.00' END
                        WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_6' ->> 'data', ''), '0')::numeric = 1 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric BETWEEN 5001 AND 10000.99
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '10,000.99' END
                        WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_6' ->> 'data', ''), '0')::numeric = 2 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric BETWEEN 10001 AND 20000.99
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '20,000.99' END
                        WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_6' ->> 'data', ''), '0')::numeric = 3 then
                            CASE WHEN (COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', ''), '0'))::numeric > 20001
                                THEN COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                            ELSE '20,001.00' END
                        ELSE
                            COALESCE(to_char((ls.report_data -> 'variable' -> 'VC_184' ->> 'data')::numeric, 'FM999,999,999,990.00')::text, '-')
                        END
                WHEN ls.formula_code IN ('FMC_9', 'FMC_10', 'FMC_19', 'FMC_20') then
                    '-'
            else
                '-'
            end AS "เงินฝากออมทรัพย์",

            CASE WHEN ls.formula_code IN ('FMC_1', 'FMC_2', 'FMC_11', 'FMC_12') then
                    '-'
                WHEN ls.formula_code IN ('FMC_3', 'FMC_4', 'FMC_13', 'FMC_14') then
                    CASE WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_4' ->> 'data', ''), '0')::numeric <> 0 then
                        CASE WHEN COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_300' ->> 'data', ''), '0')::numeric <> 0 then
                            COALESCE((ls.report_data -> 'variable' -> 'VC_300' ->> 'data')::text, '-')
                        else
                            '1'
                        END
                    else
                        COALESCE((ls.report_data -> 'variable' -> 'VC_300' ->> 'data')::text, '-')
                    END
                WHEN ls.formula_code IN ('FMC_5', 'FMC_6', 'FMC_15', 'FMC_16') then
                    CASE WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_4' ->> 'data', ''), '0')::numeric <> 0 then
                        CASE WHEN COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_300' ->> 'data', ''), '0')::numeric <> 0 then
                            COALESCE((ls.report_data -> 'variable' -> 'VC_300' ->> 'data')::text, '-')
                        else
                            '1'
                        END
                    else
                        COALESCE((ls.report_data -> 'variable' -> 'VC_300' ->> 'data')::text, '-')
                    END
                WHEN ls.formula_code IN ('FMC_7', 'FMC_8', 'FMC_17', 'FMC_18') then
                    CASE WHEN COALESCE(NULLIF(ls.report_data -> 'factorCSR' -> 'FC_6' ->> 'data', ''), '0')::numeric <> 0 then
                        CASE WHEN COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_300' ->> 'data', ''), '0')::numeric <> 0 then
                            COALESCE((ls.report_data -> 'variable' -> 'VC_300' ->> 'data')::text, '-')
                        else
                            '1'
                        END
                    else
                        COALESCE((ls.report_data -> 'variable' -> 'VC_300' ->> 'data')::text, '-')
                    END
                WHEN ls.formula_code IN ('FMC_9', 'FMC_10', 'FMC_19', 'FMC_20') then
                    '-'
            else
                '-'
            end AS "จำนวนกรมธรรม์ กับหน่วยงานอื่นๆ",

            -- log10
            COALESCE(
            to_char(
                CASE
                WHEN NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', '')::numeric > 0
                    THEN LOG(10, NULLIF(ls.report_data -> 'variable' -> 'VC_184' ->> 'data', '')::numeric)
                ELSE NULL
                END,
                'FM999,999,999,990.0000'
            )::text,
            '-'
            ) AS "log เงินฝากออมทรัพย์",

            -- อัตราส่วนภาระหนี้สินครัวเรือนต่อรายได้รวมทั้งปีของครัวเรือน
            to_char(COALESCE((
                (
                    COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_242' ->> 'data', ''), '0')::numeric
                    + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_295' ->> 'data', ''), '0')::numeric
                    + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_296' ->> 'data', ''), '0')::numeric
                )
                /
                NULLIF(
                    (
                        COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_176' ->> 'data', ''), '0')::numeric
                        + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_177' ->> 'data', ''), '0')::numeric
                        + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_178' ->> 'data', ''), '0')::numeric
                    ),
                    0
                )
            ), 0), 'FM999,999,999,990.00') AS "อัตราส่วนภาระหนี้สินครัวเรือนต่อรายได้รวมทั้งปีของครัวเรือน",
            
            -- ภาระหนี้สินครัวเรือน
            to_char((
                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_295' ->> 'data', ''), '0')::numeric
                + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_296' ->> 'data', ''), '0')::numeric
                + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_248' ->> 'data', ''), '0')::numeric
                + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_249' ->> 'data', ''), '0')::numeric
                + (
                    COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_242' ->> 'data', ''), '0')::numeric
                    - (
                        COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_248' ->> 'data', ''), '0')::numeric
                        + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_249' ->> 'data', ''), '0')::numeric
                    )
                )
            ), 'FM999,999,999,990.00') AS "ภาระหนี้สินครัวเรือน",

            -- ต้นเงินถึงกำหนดชำระของหนี้สิน ธ.ก.ส.
            to_char((
                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_242' ->> 'data', ''), '0')::numeric
                - (
                    COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_248' ->> 'data', ''), '0')::numeric
                    + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_249' ->> 'data', ''), '0')::numeric
                )
            ), 'FM999,999,999,990.00') As "ต้นเงินถึงกำหนดชำระของหนี้สิน ธ.ก.ส.",

            -- ดอกเบี้ยพึงชำระของ ธ.ก.ส.
            to_char(COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_248' ->> 'data', ''), '0')::numeric, 'FM999,999,999,990.00') AS "ดอกเบี้ยพึงชำระของ ธ.ก.ส.",

            -- ดอกเบี้ยปรับของ ธ.ก.ส.
            to_char(COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_249' ->> 'data', ''), '0')::numeric, 'FM999,999,999,990.00') AS "ดอกเบี้ยปรับของ ธ.ก.ส.",

            -- ต้นเงินถึงกำหนดชำระของหนี้สินอื่น นอกจาก ธ.ก.ส.
            to_char((
                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_295' ->> 'data', ''), '0')::numeric
                + COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_296' ->> 'data', ''), '0')::numeric
            ), 'FM999,999,999,990.00') AS "ต้นเงินถึงกำหนดชำระของหนี้สินอื่น นอกจาก ธ.ก.ส.",

            -- การจัดชั้นลูกค้าตามโครงสร้างอัตราดอกเบี้ยเงินกู้
            CASE WHEN ls.formula_code IN ('FMC_9', 'FMC_10') then
                    CASE WHEN ls.cust_type = '600' then
                        'B'
                    WHEN ls.cust_type = '603' then
                        CASE WHEN (
                                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_257' ->> 'data', ''), '0')::numeric
                                - COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_251' ->> 'data', ''), '0')::numeric
                            ) = 2 then
                            'A'
                        WHEN (
                                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_257' ->> 'data', ''), '0')::numeric
                                - COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_251' ->> 'data', ''), '0')::numeric
                            ) = 4 then
                            'AA'
                        WHEN (
                                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_257' ->> 'data', ''), '0')::numeric
                                - COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_251' ->> 'data', ''), '0')::numeric
                            ) = 6 then
                            'AAA'
                        WHEN (
                                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_257' ->> 'data', ''), '0')::numeric
                                - COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_251' ->> 'data', ''), '0')::numeric
                            ) = 8 then
                            'AAA+'
                        ELSE '-' END
                    ELSE '-'END
                WHEN ls.formula_code IN ('FMC_19', 'FMC_20') then
                    CASE WHEN ls.cust_type = '600' then
                        'B'
                    WHEN ls.cust_type = '603' then
                        CASE WHEN (
                                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_257' ->> 'data', ''), '0')::numeric
                                - COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_250' ->> 'data', ''), '0')::numeric
                            ) = 2 then
                            'A'
                        WHEN (
                                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_257' ->> 'data', ''), '0')::numeric
                                - COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_250' ->> 'data', ''), '0')::numeric
                            ) = 4 then
                            'AA'
                        WHEN (
                                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_257' ->> 'data', ''), '0')::numeric
                                - COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_250' ->> 'data', ''), '0')::numeric
                            ) = 6 then
                            'AAA'
                        WHEN (
                                COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_257' ->> 'data', ''), '0')::numeric
                                - COALESCE(NULLIF(ls.report_data -> 'variable' -> 'VC_250' ->> 'data', ''), '0')::numeric
                            ) = 8 then
                            'AAA+'
                        ELSE '-' END
                    ELSE '-' END
            else
                '-'
            end AS "การจัดชั้นลูกค้าตามโครงสร้างอัตราดอกเบี้ยเงินกู้",
            
            -- collateral from flow loan request
            to_char(
                    (coalesce(SUM(CASE WHEN b.collateral_group NOT IN ('12','13','14','15') THEN COALESCE(b.appraisal_value,0) end),0)+
                    coalesce(SUM(CASE WHEN b.collateral_group IN ('12','13','14','15') THEN COALESCE(b.pledged_amount,0) END),0))
                    ::numeric,'FM999,999,999,990.00') as "มูลค่าหลักประกัน",
                    COALESCE((
                SELECT string_agg(collateral_type::text, ',' ORDER BY collateral_type::int) AS collateral_type_list
                FROM col_type c
                where ls.cif_no = c.cif_id 
                and ls.loan_request_id = c.loan_request_id
            ), '-') AS "ประเภทหลักประกันใหม่ (กำหนดเป็นรหัส)",
            '1 : อสังหาริมทรัพย์ (ที่ดิน ที่ดินพร้อมสิ่งปลูกสร้าง สิ่งปลูกสร้าง คอนโดมิเนียมห้องชุด)' AS "หลักประกันใหม่ที่ 1",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '01' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 1",
            '2 : ส.ป.ก. กสน. น.ค' AS "หลักประกันใหม่ที่ 2",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '02' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 2",
            '3 : สังหาริมทรัพย์พิเศษ (เครื่องจักร)' AS "หลักประกันใหม่ที่ 3",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '03' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 3",
            '4 : สังหาริมทรัพย์พิเศษ (เรือ)' AS "หลักประกันใหม่ที่ 4",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '04' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 4",
            '5 : ไม้ยืนต้น' AS "หลักประกันใหม่ที่ 5",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '05' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 5",
            '6 : สิทธิการเช่า' AS "หลักประกันใหม่ที่ 6",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '06' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 6",
            '7 : สิทธิการแปลงสินทรัพย์เป็นทุน (หนังสือรับรองเอกสิทธิ ใบอนุญาต สิทธิบัตร อนุสิทธิบัตร และเครื่องหมายการค้า)' AS "หลักประกันใหม่ที่ 7",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '07' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 7",
            '8 : โอนสิทธิเรียกร้องการรับเงิน' AS "หลักประกันใหม่ที่ 8",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '08' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 8",
            '9 : รถยนต์/รถจักรยานยนต์' AS "หลักประกันใหม่ที่ 9",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '09' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 9",
            '10 : จำนำใบหุ้น พันธบัตรรัฐบาล พันธบัตร ธ.ก.ส. และพันธบัตรสถาบันการเงินอื่น' AS "หลักประกันใหม่ที่ 10",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '10' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 10",
            '11 : สลาก' AS "หลักประกันใหม่ที่ 11",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '11' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 11",
            '12 : บุคคลค้ำประกัน' AS "หลักประกันใหม่ที่ 12",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '12' THEN b.pledged_amount  END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 12",
            '13 : บุคคลค้ำประกันแบบรับรองรับผิดอย่างลูกหนี้ร่วมกัน' AS "หลักประกันใหม่ที่ 13",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '13' THEN b.pledged_amount  END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 13",
            '14 : บุคคลค้ำประกันแบบคณะกรรมการค้ำประกัน' AS "หลักประกันใหม่ที่ 14",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '14' THEN b.pledged_amount  END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 14",
            '15 : นิติบุคคลค้ำประกัน' AS "หลักประกันใหม่ที่ 15",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '15' THEN b.pledged_amount  END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 15",
            '16 : การจำนำผลิตผลและจำนำประทวน' AS "หลักประกันใหม่ที่ 16",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '16' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 16",
            '17 : หนังสือค้ำประกันบรรษัทประกันสินเชื่ออุตสาหกรรมขนาดย่อย (บสย.)' AS "หลักประกันใหม่ที่ 17",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '17' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 17",
            '18 : หนังสือรับรองสิทธิ (บำเหน็จตกทอด)' AS "หลักประกันใหม่ที่ 18",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '18' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 18",
            '19 : หนังสือค้ำประกัน (อื่นๆ)' AS "หลักประกันใหม่ที่ 19",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '19' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 19",
            '20 : เงินฝากค้ำประกัน' AS "หลักประกันใหม่ที่ 20",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '20' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 20",
            '21 : สินค้าคงคลัง (Packing Stock)' AS "หลักประกันใหม่ที่ 21",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '21' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 21",
            '22 : ตั๋วเงิน (ตั๋วสัญญาใช้เงิน ตั๋วแลกเงิน เช็ค)' AS "หลักประกันใหม่ที่ 22",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '22' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 22",
            '23 : หลักประกันอื่นนอกเหนือจาก 1-22' AS "หลักประกันใหม่ที่ 23",
            COALESCE(to_char(SUM(CASE WHEN b.collateral_group = '23' THEN b.appraisal_value END)::numeric,'FM999,999,999,990.00')::text, '-') AS "มูลค่าใหม่ที่ 23"

        FROM loan_scope ls 
        left outer JOIN base a  ON a.loan_request_id = ls.loan_request_id
        left outer JOIN base_new b ON b.loan_request_id = ls.loan_request_id
        GROUP BY
            ls.cif_no,
            ls.loan_request_id,
            ls.assessment_no,
            ls.assessment_type,
            ls.total_dept_dbm,
            ls.total_loan_request_amount,
            ls.sum_debt_loan_amount,
            ls.integrate_data,
            ls.report_data,
            ls.formula_code,
            ls.cust_type,
            ls.businessType1,
            ls.businessType1Desc,
            ls.businessType2,
            ls.businessType2Desc,
            ls.businessType3,
            ls.businessType3Desc,
            ls.mainProductType,
            ls.mainProductTypeDesc,
            ls.productTypeObjective,
            ls.productTypeObjectiveDesc
        ORDER BY ls.cif_no, ls.loan_request_id
    ),
	-- select * from ltvr_code
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
        select  lv."เลขที่ใบประเมิน" ,
            COALESCE(NULLIF(REPLACE(lv."LTVR", ',', ''), '-'), '0')::numeric * COALESCE(NULLIF((frs.coeff_arr_norm->>0),'')::numeric, 0) ,
                b.formula_code
        from  ltvr_code lv
        join base b on lv."เลขที่ใบประเมิน" = b.assessment_no
        join factor_rs frs on frs.formula_code = b.formula_code
                        and frs.assessment_no = b.assessment_no
                        and frs.factor_name = 'LTVR'
        ) out
        group by out.assessment_no ,formula_code
    ),
	-- select * from x_value
	csr_criteria AS (
		select * from lps_corporate_loan.mas_corp_assessment_csr_criteria
	),
	-- select * from csr_criteria
	calc_value as (
	select
		*
	from csr_criteria csr 
	join x_value frm on frm.formula_code = csr.formula_code
	where (csr.minimum_pd is null and ROUND(frm.PD, 4) < csr.maximum_pd) or (csr.maximum_pd is null and ROUND(frm.PD, 4) >= csr.minimum_pd) or (ROUND(frm.PD, 4) >= csr.minimum_pd and ROUND(frm.PD, 4) <= csr.maximum_pd)
	)
	--select * from calc_value
        /* ===================== Output ===================== */	
    select 
    	ltv.*,
    	ROUND(cal.PD, 4) AS "Result_PD",
		cal.minimum_score::int || '-' || cal.maximum_score::int AS "Result_ช่วงคะแนนสินเชื่อ",
		cal.result_desc  AS "Result_อันดับชั้นความเสี่ยง",
		((cal.interest_rate_spread)::numeric + (select ((results_score->'CSR'->'answer'->'SSC_2'->>'pricing')::numeric - (results_score->'CSR'->'answer'->'SSC_2'->>'interest_rate_spread')::numeric) from cif.mas_assessment_answer ans where ans.assessment_no = cal.assessment_no)) AS "Result_อัตราดอกเบี้ยที่ได้รับ",
		cal.grade_desc AS "Result_ระดับคุณภาพหนี้",
		CASE
		    WHEN cal."isPass" = TRUE THEN 'ผ่าน'
		    WHEN cal."isPass" = FALSE THEN 'ไม่ผ่าน'
		END AS "Result_เกณฑ์ประเมินตามระบบ"
    from ltvr_code	ltv
    join calc_value cal on cal.assessment_no = ltv."เลขที่ใบประเมิน"



