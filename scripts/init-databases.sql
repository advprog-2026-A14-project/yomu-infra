-- Creates all required databases on PostgreSQL startup
-- Runs via /docker-entrypoint-initdb.d/ (docker official postgres image)
-- yomu_db is created automatically by POSTGRES_DB env var

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'yomu_engine') THEN
        CREATE DATABASE yomu_engine;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'yomu_db_staging') THEN
        CREATE DATABASE yomu_db_staging;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'yomu_engine_staging') THEN
        CREATE DATABASE yomu_engine_staging;
    END IF;
END
$$;

GRANT ALL PRIVILEGES ON DATABASE yomu_engine TO postgres;
GRANT ALL PRIVILEGES ON DATABASE yomu_db_staging TO postgres;
GRANT ALL PRIVILEGES ON DATABASE yomu_engine_staging TO postgres;
