-- One-shot init for docker-compose Postgres (POSTGRES_DB=mydb).
DO $$ BEGIN
  CREATE ROLE rest_app LOGIN PASSWORD 'devops123';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE ROLE grpc_app LOGIN PASSWORD 'devops123';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE ROLE graphql_app LOGIN PASSWORD 'devops123';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

GRANT ALL PRIVILEGES ON DATABASE mydb TO rest_app, grpc_app, graphql_app;

CREATE TABLE IF NOT EXISTS rest_device (
  id SERIAL PRIMARY KEY,
  uuid TEXT NOT NULL,
  mac TEXT NOT NULL,
  firmware TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS grpc_device (LIKE rest_device INCLUDING ALL);
CREATE TABLE IF NOT EXISTS graphql_device (LIKE rest_device INCLUDING ALL);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rest_app, grpc_app, graphql_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO rest_app, grpc_app, graphql_app;
