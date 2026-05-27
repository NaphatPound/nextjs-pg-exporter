WITH last_4_year AS ( 
    select
    	maa.assessment_no,
    	maa.application_id as loan_request_id,
        maa.cif_no,
        maa.assessment_type,
        fin.*,
        ROW_NUMBER() OVER (
            PARTITION BY fin.application_id
            ORDER BY fin.data_year DESC
        ) rn
    FROM cif.mas_assessment_answer maa
    LEFT JOIN cif.trn_customer_fin_stmt fin
      ON maa.application_id = fin.application_id
    WHERE maa.approved_date BETWEEN 
              to_timestamp('2025-12-01 00:00:00.000','yyyy-mm-dd HH24:MI:SS.MS')
          AND to_timestamp('2025-12-30 23:59:59.999','yyyy-mm-dd HH24:MI:SS.MS')
      AND maa.is_export_csv = true
      AND fin.financial_type = 'SAVINGS_COOPERATIVE'
      AND maa.assessment_type IN ('CREATE_LOAN','CHANGE_LOAN','OVERDRAFT')
      
      UNION all
      -- ======================= CREATE_DBM =======================
      select
    	maa.assessment_no,
    	maa.application_id as loan_request_id,
        maa.cif_no,
        maa.assessment_type,
        fin.*,
        ROW_NUMBER() OVER (
            PARTITION BY fin.application_id
            ORDER BY fin.data_year DESC
        ) rn
    FROM cif.mas_assessment_answer maa
    LEFT JOIN cif.trn_customer_fin_stmt fin
      ON maa.application_id = fin.application_id
    WHERE maa.approved_date BETWEEN 
              to_timestamp('2025-12-01 00:00:00.000','yyyy-mm-dd HH24:MI:SS.MS')
          AND to_timestamp('2025-12-30 23:59:59.999','yyyy-mm-dd HH24:MI:SS.MS')
      AND maa.is_export_csv = true
      AND fin.financial_type = 'SAVINGS_COOPERATIVE'
      AND maa.assessment_type IN ('CREATE_DBM','CHANGE_LOAN','AUTO_DBM')
      
      UNION all
      -- ======================= CPL CREATE_DBM =======================
      select
    	maa.assessment_no,
    	maa.application_id as loan_request_id,
        maa.cif_no,
        maa.assessment_type,
        fin.*,
        ROW_NUMBER() OVER (
            PARTITION BY fin.application_id
            ORDER BY fin.data_year DESC
        ) rn
    FROM cif.mas_assessment_answer maa
    LEFT JOIN disbursement.trn_corp_disbursement corp_dbm
      ON maa.application_id = corp_dbm.disburse_no
    LEFT JOIN lps_corporate_loan.corp_loan_request corp_loan
      ON corp_dbm.loan_account = corp_loan.loan_account
    LEFT JOIN cif.trn_customer_fin_stmt fin
      ON corp_loan.loan_request_id = fin.application_id
    WHERE maa.approved_date BETWEEN 
              to_timestamp('2025-12-01 00:00:00.000','yyyy-mm-dd HH24:MI:SS.MS')
          AND to_timestamp('2025-12-30 23:59:59.999','yyyy-mm-dd HH24:MI:SS.MS')
      AND maa.is_export_csv = true
      AND fin.financial_type = 'SAVINGS_COOPERATIVE'
      AND maa.assessment_type IN ('CREATE_DBM')
      
      UNION all
      -- ======================= RTL CREATE_DBM =======================
      select
    	maa.assessment_no,
    	maa.application_id as loan_request_id,
        maa.cif_no,
        maa.assessment_type,
        fin.*,
        ROW_NUMBER() OVER (
            PARTITION BY fin.application_id
            ORDER BY fin.data_year DESC
        ) rn
    FROM cif.mas_assessment_answer maa
    LEFT JOIN disbursement.trn_disbursement retail_dbm
      ON maa.application_id = retail_dbm.disburse_no
    LEFT JOIN lps_retail_loan.loan_request retail_loan
      ON retail_dbm.loan_account = retail_loan.loan_account
    LEFT JOIN cif.trn_customer_fin_stmt fin
      ON retail_loan.loan_request_id = fin.application_id
    WHERE maa.approved_date BETWEEN 
              to_timestamp('2025-12-01 00:00:00.000','yyyy-mm-dd HH24:MI:SS.MS')
          AND to_timestamp('2025-12-30 23:59:59.999','yyyy-mm-dd HH24:MI:SS.MS')
      AND maa.is_export_csv = true
      AND fin.financial_type = 'SAVINGS_COOPERATIVE'
      AND maa.assessment_type IN ('CREATE_DBM')
      
      UNION all
      -- ======================= CPL CHANGE_DBM =======================
      select
    	maa.assessment_no,
    	maa.application_id as loan_request_id,
        maa.cif_no,
        maa.assessment_type,
        fin.*,
        ROW_NUMBER() OVER (
            PARTITION BY fin.application_id
            ORDER BY fin.data_year DESC
        ) rn
    FROM cif.mas_assessment_answer maa
    LEFT JOIN disbursement.trn_change_disbursement corp_dbm
      ON maa.application_id = corp_dbm.disburse_no
    LEFT JOIN lps_corporate_loan.corp_loan_request corp_loan
      ON corp_dbm.loan_account = corp_loan.loan_account
    LEFT JOIN cif.trn_customer_fin_stmt fin
      ON corp_loan.loan_request_id = fin.application_id
    WHERE maa.approved_date BETWEEN 
              to_timestamp('2025-12-01 00:00:00.000','yyyy-mm-dd HH24:MI:SS.MS')
          AND to_timestamp('2025-12-30 23:59:59.999','yyyy-mm-dd HH24:MI:SS.MS')
      AND maa.is_export_csv = true
      AND fin.financial_type = 'SAVINGS_COOPERATIVE'
      AND maa.assessment_type IN ('CHANGE_DBM')
      
      UNION all
      -- ======================= RTL CHANGE_DBM =======================
      select
    	maa.assessment_no,
    	maa.application_id as loan_request_id,
        maa.cif_no,
        maa.assessment_type,
        fin.*,
        ROW_NUMBER() OVER (
            PARTITION BY fin.application_id
            ORDER BY fin.data_year DESC
        ) rn
    FROM cif.mas_assessment_answer maa
    LEFT JOIN disbursement.trn_change_disbursement retail_dbm
      ON maa.application_id = retail_dbm.disburse_no
    LEFT JOIN lps_retail_loan.loan_request retail_loan
      ON retail_dbm.loan_account = retail_loan.loan_account
    LEFT JOIN cif.trn_customer_fin_stmt fin
      ON retail_loan.loan_request_id = fin.application_id
    WHERE maa.approved_date BETWEEN 
              to_timestamp('2025-12-01 00:00:00.000','yyyy-mm-dd HH24:MI:SS.MS')
          AND to_timestamp('2025-12-30 23:59:59.999','yyyy-mm-dd HH24:MI:SS.MS')
      AND maa.is_export_csv = true
      AND fin.financial_type = 'SAVINGS_COOPERATIVE'
      AND maa.assessment_type IN ('CHANGE_DBM')
      
      UNION all
      -- ======================= CPL AUTO_DBM =======================
      select
    	maa.assessment_no,
    	maa.application_id as loan_request_id,
        maa.cif_no,
        maa.assessment_type,
        fin.*,
        ROW_NUMBER() OVER (
            PARTITION BY fin.application_id
            ORDER BY fin.data_year DESC
        ) rn
    FROM cif.mas_assessment_answer maa
    LEFT JOIN lps_corporate_loan.corp_loan_request corp_loan
      ON maa.application_id = corp_loan.disburse_no
    LEFT JOIN cif.trn_customer_fin_stmt fin
      ON corp_loan.loan_request_id = fin.application_id
    WHERE maa.approved_date BETWEEN 
              to_timestamp('2025-12-01 00:00:00.000','yyyy-mm-dd HH24:MI:SS.MS')
          AND to_timestamp('2025-12-30 23:59:59.999','yyyy-mm-dd HH24:MI:SS.MS')
      AND maa.is_export_csv = true
      AND fin.financial_type = 'SAVINGS_COOPERATIVE'
      AND maa.assessment_type IN ('AUTO_DBM')
      
      UNION all
      -- ======================= RTL AUTO_DBM =======================
      select
    	maa.assessment_no,
    	maa.application_id as loan_request_id,
        maa.cif_no,
        maa.assessment_type,
        fin.*,
        ROW_NUMBER() OVER (
            PARTITION BY fin.application_id
            ORDER BY fin.data_year DESC
        ) rn
    FROM cif.mas_assessment_answer maa
    LEFT JOIN lps_retail_loan.loan_cap_information retail_loan
      ON maa.application_id = retail_loan.disburse_no
    LEFT JOIN cif.trn_customer_fin_stmt fin
      ON retail_loan.loan_request_id = fin.application_id
    WHERE maa.approved_date BETWEEN 
              to_timestamp('2025-12-01 00:00:00.000','yyyy-mm-dd HH24:MI:SS.MS')
          AND to_timestamp('2025-12-30 23:59:59.999','yyyy-mm-dd HH24:MI:SS.MS')
      AND maa.is_export_csv = true
      AND fin.financial_type = 'SAVINGS_COOPERATIVE'
      AND maa.assessment_type IN ('AUTO_DBM')
)
SELECT
    t.assessment_no  AS "เลขประเมินความเสี่ยง",
    t.loan_request_id AS "เลขใบงาน",
    t.cif_no          AS "CIF",
    t.assessment_type AS "ประเภทแบบประเมิน",
    
    /* SAVINGS_COOPERATIVE */
    /* 08010100 หนี้ชำระไม่ได้ตามกำหนด */
    MAX((elem->>'accountValue')::numeric) FILTER (WHERE elem->>'accountCode' = '08010100' AND rn = 1) AS "หนี้ชำระไม่ได้ตามกำหนด",
    MAX((elem->>'accountValue')::numeric) FILTER (WHERE elem->>'accountCode' = '08010100' AND rn = 2) AS "หนี้ชำระไม่ได้ตามกำหนด -1",
    MAX((elem->>'accountValue')::numeric) FILTER (WHERE elem->>'accountCode' = '08010100' AND rn = 3) AS "หนี้ชำระไม่ได้ตามกำหนด -2",
    MAX((elem->>'accountValue')::numeric) FILTER (WHERE elem->>'accountCode' = '08010100' AND rn = 4) AS "หนี้ชำระไม่ได้ตามกำหนด -3",

    /* 08010200 หนี้ถึงกำหนดชำระ */
    MAX((elem->>'accountValue')::numeric) FILTER (WHERE elem->>'accountCode' = '08010200' AND rn = 1) AS "หนี้ถึงกำหนดชำระ",
    MAX((elem->>'accountValue')::numeric) FILTER (WHERE elem->>'accountCode' = '08010200' AND rn = 2) AS "หนี้ถึงกำหนดชำระ -1",
    MAX((elem->>'accountValue')::numeric) FILTER (WHERE elem->>'accountCode' = '08010200' AND rn = 3) AS "หนี้ถึงกำหนดชำระ -2",
    MAX((elem->>'accountValue')::numeric) FILTER (WHERE elem->>'accountCode' = '08010200' AND rn = 4) AS "หนี้ถึงกำหนดชำระ -3"

FROM last_4_year t
CROSS JOIN LATERAL jsonb_array_elements(t.fin_ratio_data::jsonb) elem
GROUP BY
    t.assessment_no,
    t.loan_request_id,
    t.cif_no,
    t.assessment_type;