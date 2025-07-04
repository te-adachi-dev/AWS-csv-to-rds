CREATE TABLE IF NOT EXISTS sfc_accounts (
    -- 基本情報
    id VARCHAR(18) NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    master_record_id VARCHAR(18),
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50),
    record_type_id VARCHAR(18) NOT NULL,
    parent_id VARCHAR(18),
    
    -- 請求先住所情報
    billing_street VARCHAR(255),
    billing_city VARCHAR(40),
    billing_state VARCHAR(80),
    billing_postal_code VARCHAR(20),
    billing_country VARCHAR(80),
    billing_latitude NUMERIC(18,15),
    billing_longitude NUMERIC(18,15),
    billing_geocode_accuracy VARCHAR(50),
    billing_address TEXT,
    
    -- 納入先住所情報
    shipping_street VARCHAR(255),
    shipping_city VARCHAR(40),
    shipping_state VARCHAR(80),
    shipping_postal_code VARCHAR(20),
    shipping_country VARCHAR(80),
    shipping_latitude NUMERIC(18,15),
    shipping_longitude NUMERIC(18,15),
    shipping_geocode_accuracy VARCHAR(18),
    shipping_address TEXT,
    
    -- 連絡先情報
    phone VARCHAR(40),
    fax VARCHAR(40),
    website VARCHAR(255),
    photo_url VARCHAR(255),
    
    -- 企業情報
    sic VARCHAR(20),
    industry TEXT,
    annual_revenue NUMERIC(18,2),
    number_of_employees INTEGER,
    ownership VARCHAR(50),
    ticker_symbol VARCHAR(20),
    description TEXT,
    rating VARCHAR(50),
    currency_iso_code VARCHAR(10),
    
    -- システム情報（39番は欠番のためスキップ）
    created_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by_id VARCHAR(18) NOT NULL,
    last_modified_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_modified_by_id VARCHAR(18) NOT NULL,
    system_modstamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_activity_date DATE,
    last_viewed_date TIMESTAMP WITH TIME ZONE,
    last_referenced_date TIMESTAMP WITH TIME ZONE,
    
    -- パートナー情報
    is_partner BOOLEAN DEFAULT FALSE,
    channel_program_name VARCHAR(255),
    channel_program_level_name VARCHAR(255),
    
    -- 外部連携情報
    jigsaw VARCHAR(20),
    jigsaw_company_id VARCHAR(20),
    account_source VARCHAR(50),
    sic_desc VARCHAR(80),
    operating_hours_id VARCHAR(18),
    
    -- YMC関連カスタム項目（56-268）
    ymc_s_customer_code_c VARCHAR(100),
    ymc_s_furigana_c VARCHAR(255),
    ymc_s_ymcsales_rep_name_c VARCHAR(255),
    ymc_s_industry_c VARCHAR(255),
    ymc_s_area_c VARCHAR(255),
    ymc_s_distributor_name_c VARCHAR(255),
    ymc_s_country_prefecture_c VARCHAR(255),
    ymc_s_sales_distributor_code_c VARCHAR(5),
    ymc_s_sales_distributor_name_c VARCHAR(255),
    ymc_s_sales_distributor_name_kana_c VARCHAR(255),
    ymc_s_sales_distributor_address1_c VARCHAR(501),
    ymc_s_sales_distributor_address2_c VARCHAR(255),
    ymc_s_service_distributor_code_c VARCHAR(5),
    ymc_s_service_distributor_name_c VARCHAR(255),
    ymc_s_service_distributor_name_kana_c VARCHAR(255),
    ymc_s_service_distributor_address1_c VARCHAR(255),
    ymc_s_service_distributor_address2_c VARCHAR(255),
    
    -- 成約情報
    csm_sfdc_ruiseki_lost_amount_c NUMERIC(18,2),
    ruisekisei_yaku_kaisuu_c INTEGER,
    sfdc_latest_closed_date_c DATE,
    sfdc_ruiseki_close_amount_c NUMERIC(18,2),
    
    -- グループ顧客情報
    group_common_custmer_name_c VARCHAR(30),
    group_common_custmer_code_c VARCHAR(6),
    
    -- 2次販売代理店情報
    ymc_s_sales_distributor_name_2_c VARCHAR(255),
    ymc_s_group_management_code_c VARCHAR(50),
    ymc_s_sales_distributor_code_2_c VARCHAR(5),
    ymc_s_sales_distributor_name_kana_2_c VARCHAR(255),
    
    -- 取引先分類情報
    ymc_s_account_category_c VARCHAR(50),
    ymc_s_distributor_code_c VARCHAR(5),
    ymc_c_owned_line_c VARCHAR(255),
    ymc_x_sell_c BOOLEAN DEFAULT FALSE,
    dis_name_c VARCHAR(255),
    
    -- 他システム顧客コード
    skw_customer_code_c VARCHAR(30),
    ayc_customer_code_c VARCHAR(30),
    ymc_cust_country_c VARCHAR(50),
    skw_short_customer_name_c VARCHAR(30),
    skw_sales_office_c VARCHAR(30),
    ymc_cyoku_code_c VARCHAR(1),
    
    -- PFA関連
    pfa_area_c VARCHAR(30),
    pfa_short_customer_name_c VARCHAR(30),
    pfa_customer_code_c VARCHAR(30),
    
    -- AYC関連
    ayc_short_customer_name_c VARCHAR(30),
    ayc_area_c VARCHAR(255),
    ayc_country_prefecture_c VARCHAR(255),
    
    -- その他基本情報
    short_customer_name_c VARCHAR(30),
    skw_area_c VARCHAR(30),
    ymc_distributor_code_c VARCHAR(4),
    ymc_sales_agency_tanto_code_text_c VARCHAR(4),
    
    -- カスタマー申請情報
    ymc_s_cvalid_date_c DATE,
    ymc_s_cust_kana_c VARCHAR(200),
    ymc_s_cust_code_c VARCHAR(5),
    ymc_s_del_flg_c VARCHAR(1),
    ymc_s_kubun_c VARCHAR(50),
    ymc_s_sales_agency_c VARCHAR(255),
    
    -- 特定顧客フラグ
    ymc_vip_cust_c BOOLEAN DEFAULT FALSE,
    ymc_email_c VARCHAR(255),
    ymc_area_c TEXT,
    ymc_transaction_examination_deadline_status_c TEXT,
    mc_s_sales_agency_tanto_code_c TEXT,
    ymc_bikou_c TEXT,
    ymc_brndkbn_c VARCHAR(50),
    ymc_contract_asset_mail_c BOOLEAN DEFAULT FALSE,
    
    -- 作成情報（重複）
    ymc_cre_date_c TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ymc_cre_prg_c VARCHAR(10),
    
    -- 英語名・カナ名情報
    ymc_custkana1_c VARCHAR(25),
    ymc_custkana2_c VARCHAR(25),
    ymc_cust_kana_c VARCHAR(20),
    ymc_custkname_c VARCHAR(20),
    
    -- 代理店情報
    ymc_d_syubetu_c VARCHAR(50),
    ymc_delflg_c BOOLEAN DEFAULT FALSE,
    ymc_external_id2_c VARCHAR(255),
    ymc_external_id_c VARCHAR(255),
    
    -- システムフラグ
    ymc_fa_flag_c BOOLEAN DEFAULT FALSE,
    ymc_fqdn_c VARCHAR(255),
    ymc_imtantou_c VARCHAR(255),
    
    -- 受注・決済情報
    ymc_jyukbn_c VARCHAR(50),
    ymc_ken_code_c VARCHAR(3),
    ymc_kesaikbn_c VARCHAR(50),
    ymc_konkaikin_c NUMERIC(18,2),
    ymc_konkaiym_c DATE,
    
    -- 環境・言語情報
    ymc_line_environment_c TEXT,
    ymc_local_language_c VARCHAR(255),
    
    -- レポート用フラグ
    ymc_new24h_support_c BOOLEAN DEFAULT FALSE,
    ymc_new_remote_c BOOLEAN DEFAULT FALSE,
    ymc_nohin_flg_c VARCHAR(1),
    
    -- 入金情報
    ymc_nyukin_c NUMERIC(18,2),
    ymc_nyukinym_c DATE,
    
    -- 仕切率・その他
    ymc_p_sikiri_c NUMERIC(3,0),
    ymc_post_c VARCHAR(7),
    ymc_report_latest_expiration_date_24h_c DATE,
    ymc_report_latest_expiration_date_remote_c DATE,
    ymc_report_oldest_expiration_date_remote_c DATE,
    ymc_smt_flag_c BOOLEAN DEFAULT FALSE,
    
    -- 住所・担当者情報
    ymc_s_address_c VARCHAR(200),
    ymc_s_annai_tanto_c VARCHAR(255),
    ymc_s_buhin_tanto_c VARCHAR(255),
    ymc_s_cconsent_no_c VARCHAR(10),
    ymc_s_cim_no_c VARCHAR(7),
    ymc_s_comm2_c TEXT,
    ymc_s_comm_c TEXT,
    
    -- 顧客詳細情報
    ymc_s_cust_country_c VARCHAR(5),
    ymc_s_cust_eng_c VARCHAR(60),
    ymc_s_cust_kana_key_c VARCHAR(255),
    ymc_s_cust_lang_c VARCHAR(60),
    ymc_s_cust_name2_c VARCHAR(200),
    ymc_s_distributor_c VARCHAR(255),
    ymc_s_fst_syukyymm_c DATE,
    ymc_s_g_port_code_c VARCHAR(4),
    
    -- 交通費情報
    ymc_s_interchange_kin_c NUMERIC(6,0),
    ymc_s_interchange_c VARCHAR(50),
    ymc_s_jyuyou_c BOOLEAN DEFAULT FALSE,
    ymc_s_kenen_c BOOLEAN DEFAULT FALSE,
    ymc_s_new_cust_c VARCHAR(255),
    ymc_s_sales_agency_tanto_c VARCHAR(255),
    ymc_s_second_agency_code_c VARCHAR(50),
    ymc_s_service_agency_c VARCHAR(255),
    ymc_s_staion_kin_c NUMERIC(7,0),
    ymc_s_staion_c VARCHAR(50),
    ymc_s_stock_end_c BOOLEAN DEFAULT FALSE,
    ymc_s_syubetu_c VARCHAR(50),
    
    -- ユーザー区分
    ymc_s_user_kbn1_c VARCHAR(50),
    ymc_s_user_kbn2_c VARCHAR(50),
    ymc_s_user_kbn3_c VARCHAR(50),
    
    -- 2次代理店情報
    ymc_second_agency_code_c VARCHAR(5),
    ymc_second_agency_info_c VARCHAR(20),
    ymc_second_agency_name_c VARCHAR(200),
    
    -- 請求・決済情報
    ymc_seikyukbn_c VARCHAR(4),
    ymc_sikiri_c NUMERIC(18,2),
    ymc_simebi_c INTEGER,
    ymc_stop_flg_c BOOLEAN DEFAULT FALSE,
    ymc_system_line_c NUMERIC(18,0),
    ymc_tantou_c VARCHAR(12),
    ymc_tegatakin_c NUMERIC(18,2),
    
    -- 移動費用情報
    ymc_travel_expenses_unit_price_detail_c TEXT,
    ymc_travel_expenses_unit_price_hamamatsu_c NUMERIC(18,2),
    ymc_travel_expenses_unit_price_kansai_c NUMERIC(18,2),
    ymc_travel_expenses_unit_price_kanto_c NUMERIC(18,2),
    ymc_travel_expenses_unit_price_kyushu_c NUMERIC(18,2),
    
    -- 更新情報
    ymc_upd_date_c TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ymc_upd_prg_c VARCHAR(10),
    
    -- 売上情報
    ymc_uri_code_c VARCHAR(4),
    ymc_uri_name_c VARCHAR(32),
    ymc_zankin_c NUMERIC(18,2),
    ymc_zenkaikin_c NUMERIC(18,2),
    ymc_zenkaiym_c DATE,
    
    -- 継続サポート情報
    ymc_continuous24h_support_c BOOLEAN DEFAULT FALSE,
    ymc_continuous_remote_c BOOLEAN DEFAULT FALSE,
    
    -- 担当者詳細情報
    ymc_s_annai_tanto_code_c TEXT,
    ymc_s_annai_tanto_department_c TEXT,
    ymc_s_annai_tanto_mobile_phone_c TEXT,
    ymc_s_annai_tanto_phone_c TEXT,
    ymc_s_buhin_tanto_code_c TEXT,
    ymc_s_buhin_tanto_department_c TEXT,
    ymc_s_buhin_tanto_mobile_phone_c TEXT,
    ymc_s_buhin_tanto_phone_c TEXT,
    
    -- その他コード情報
    ymc_s_new_cust_code_c TEXT,
    ymc_s_sales_agency_kana_c TEXT,
    ymc_s_sales_agency_tanto_code_c TEXT,

    ymc_s_service_agency_code_c TEXT,
    ymc_s_service_agency_kana_c TEXT,
    
    -- 代表情報
    ymc_daihyou_c VARCHAR(255),
    ymc_recall_infomation_c BOOLEAN DEFAULT FALSE,
    ymc_oracle_sales_cloud_id_c VARCHAR(255),
    ymc_sales_distributor_is_self_c BOOLEAN DEFAULT FALSE,
    ymc_exist_remote_maintenance_c BOOLEAN DEFAULT FALSE,
    ymc_update_remote24h_info_trigger_c BOOLEAN DEFAULT FALSE,
    ymc_record_type_developer_name_c TEXT,
    
    -- メールアドレス
    ymc_s_buhin_tanto_email_c TEXT,
    ymc_s_annai_tanto_email_c TEXT,
    
    -- 住所全表示
    ymc_address_full_c TEXT,
    
    -- 連携フラグ
    ymc_sales_smtcust_code_linked_flg BOOLEAN DEFAULT FALSE,
    ymc_sales_cross_selling_opportunity_flg BOOLEAN DEFAULT FALSE,
    
    -- 営業関連情報
    ymc_sales_company_group_c VARCHAR(255),
    ymc_sales_department_kbn_c VARCHAR(50),
    ymc_sales_first_ship_month_c DATE,
    ymc_sales_free_coment_c TEXT,
    ymc_sales_last_update_date_c TIMESTAMP WITH TIME ZONE,
    ymc_sales_new_app_coment_c TEXT,
    ymc_sales_new_flg_c BOOLEAN DEFAULT FALSE,
    ymc_sales_duplication_c VARCHAR(255),
    ymc_sales_major_category_c TEXT,
    ymc_sales_middle_category_c TEXT,
    ymc_sales_opportunity_last_date_c DATE,
    ymc_sales_case_last_date_c DATE,
    ymc_sales_response_request_last_date_c DATE,
    
    -- 代理店グループ
    ymc_parent_id1_c VARCHAR(18),
    ymc_parent_id2_c VARCHAR(18),
    ymc_parent_id3_c VARCHAR(18),
    ymc_parent_id4_c VARCHAR(18),
    ymc_parent_id5_c VARCHAR(18),
    
    -- リレーション情報
    ymc_relation_updated_c BOOLEAN DEFAULT FALSE,
    ymc_relation_update_target_c VARCHAR(255),
    
    -- S2関連情報
    ymc_s2_dummy_client_c BOOLEAN DEFAULT FALSE,
    ymc_s2_customer_review_c TEXT,
    ymc_s2_customer_review_flag_c BOOLEAN DEFAULT FALSE,
    ymc_s2_sonota_c TEXT,
    ymc_s2_del_flg_c BOOLEAN DEFAULT FALSE,
    ymc_s2_cconsent_no_c TEXT,
    ymc_s2_cim_no_c TEXT,
    ymc_s2_cvalid_date_c DATE,
    ymc_s2_g_port_code_c TEXT,
    ymc_s2_deadline_status_c TEXT,
    
    -- 現地情報
    ymc_local_address_c TEXT,
    ymc_salesforce_id_c TEXT,
    ymc_s2_temporary_customer_c BOOLEAN DEFAULT FALSE,
    ymc_s2_uri_cust_code_c TEXT,
    
    -- DWH管理カラム
    dwh_id INTEGER NOT NULL,
    dwh_operation_type_flag INTEGER NOT NULL,
    dwh_create_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dwh_update_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dwh_source_system_code VARCHAR(10) NOT NULL
);