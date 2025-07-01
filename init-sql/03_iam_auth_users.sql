-- IAM認証用ユーザーの作成
-- 注意: PostgreSQLのマスターユーザーで実行する必要があります

-- 読み取り専用ユーザー
CREATE USER test_readonly;
GRANT rds_iam TO test_readonly;
GRANT CONNECT ON DATABASE postgres TO test_readonly;
GRANT USAGE ON SCHEMA public TO test_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO test_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO test_readonly;

-- フルアクセスユーザー
CREATE USER test_fullaccess;
GRANT rds_iam TO test_fullaccess;
GRANT CONNECT ON DATABASE postgres TO test_fullaccess;
GRANT ALL PRIVILEGES ON SCHEMA public TO test_fullaccess;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO test_fullaccess;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO test_fullaccess;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO test_fullaccess;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO test_fullaccess;

-- 制限付きアクセスユーザー（特定テーブルのみ）
CREATE USER test_limited;
GRANT rds_iam TO test_limited;
GRANT CONNECT ON DATABASE postgres TO test_limited;
GRANT USAGE ON SCHEMA public TO test_limited;

-- 注意: 特定のテーブルへのアクセス権限は、テーブル作成後に付与する必要があります
-- 例: GRANT SELECT, INSERT, UPDATE ON afc_accounts TO test_limited;

-- IAM認証の確認
SELECT 
    usename,
    usesysid,
    usesuper,
    usecreatedb,
    pg_has_role(usename, 'rds_iam', 'member') as has_iam_role
FROM 
    pg_user 
WHERE 
    usename IN ('test_readonly', 'test_fullaccess', 'test_limited')
ORDER BY 
    usename;