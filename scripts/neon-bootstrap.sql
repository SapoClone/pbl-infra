-- Provisions the Postgres side of the backend on Neon (or any Postgres 15+): one role and one schema per service.
-- Run once as the database owner, before the first deploy; it is idempotent, so re-running rotates the passwords.
--
--   psql "$ADMIN_DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -v platform_pw="$PW_PLATFORM" \
--     -v catalog_pw="$PW_CATALOG" \
--     -v customer_pw="$PW_CUSTOMER" \
--     -v inventory_pw="$PW_INVENTORY" \
--     -v sales_pw="$PW_SALES" \
--     -v finance_pw="$PW_FINANCE" \
--     -v integration_pw="$PW_INTEGRATION" \
--     -v insight_pw="$PW_INSIGHT" \
--     -f scripts/neon-bootstrap.sql
--
-- The passwords are the `database_passwords` of live/prod/secrets.tfvars (role of service X: pbl_X).
--
-- Model: pbl_<service> owns its schema, so it can run its own migrations (every service except platform migrates
-- itself at start; platform's migration runs as a one-off task). It is not a superuser, does not bypass RLS, and
-- cannot read any other service's schema. Owners are not subject to RLS unless FORCE ROW LEVEL SECURITY is set, so
-- the tenant filter in the application (TenantScopedRepository) remains the control; the roles give isolation
-- between services, not between tenants.
-- Platform's hand-written migrations create their tables in `public` whatever DATABASE_SCHEMA says, so pbl_platform
-- owns `public` and the other services get no access to it.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- platform's migrations default ids with uuid_generate_v4(); a role that is not a superuser cannot create the extension itself
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- PUBLIC may use `public` (extension functions) but never create objects in it
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- platform
SELECT 'CREATE ROLE pbl_platform LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pbl_platform') \gexec
ALTER ROLE pbl_platform LOGIN PASSWORD :'platform_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
GRANT USAGE, CREATE ON SCHEMA public TO pbl_platform;

-- catalog
SELECT 'CREATE ROLE pbl_catalog LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pbl_catalog') \gexec
ALTER ROLE pbl_catalog LOGIN PASSWORD :'catalog_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE SCHEMA IF NOT EXISTS catalog AUTHORIZATION pbl_catalog;
REVOKE ALL ON SCHEMA catalog FROM PUBLIC;
ALTER ROLE pbl_catalog SET search_path = catalog, public;

-- customer
SELECT 'CREATE ROLE pbl_customer LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pbl_customer') \gexec
ALTER ROLE pbl_customer LOGIN PASSWORD :'customer_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE SCHEMA IF NOT EXISTS customer AUTHORIZATION pbl_customer;
REVOKE ALL ON SCHEMA customer FROM PUBLIC;
ALTER ROLE pbl_customer SET search_path = customer, public;

-- inventory
SELECT 'CREATE ROLE pbl_inventory LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pbl_inventory') \gexec
ALTER ROLE pbl_inventory LOGIN PASSWORD :'inventory_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE SCHEMA IF NOT EXISTS inventory AUTHORIZATION pbl_inventory;
REVOKE ALL ON SCHEMA inventory FROM PUBLIC;
ALTER ROLE pbl_inventory SET search_path = inventory, public;

-- sales
SELECT 'CREATE ROLE pbl_sales LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pbl_sales') \gexec
ALTER ROLE pbl_sales LOGIN PASSWORD :'sales_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE SCHEMA IF NOT EXISTS sales AUTHORIZATION pbl_sales;
REVOKE ALL ON SCHEMA sales FROM PUBLIC;
ALTER ROLE pbl_sales SET search_path = sales, public;

-- finance
SELECT 'CREATE ROLE pbl_finance LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pbl_finance') \gexec
ALTER ROLE pbl_finance LOGIN PASSWORD :'finance_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE SCHEMA IF NOT EXISTS finance AUTHORIZATION pbl_finance;
REVOKE ALL ON SCHEMA finance FROM PUBLIC;
ALTER ROLE pbl_finance SET search_path = finance, public;

-- integration
SELECT 'CREATE ROLE pbl_integration LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pbl_integration') \gexec
ALTER ROLE pbl_integration LOGIN PASSWORD :'integration_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE SCHEMA IF NOT EXISTS integration AUTHORIZATION pbl_integration;
REVOKE ALL ON SCHEMA integration FROM PUBLIC;
ALTER ROLE pbl_integration SET search_path = integration, public;

-- insight
SELECT 'CREATE ROLE pbl_insight LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pbl_insight') \gexec
ALTER ROLE pbl_insight LOGIN PASSWORD :'insight_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE SCHEMA IF NOT EXISTS insight AUTHORIZATION pbl_insight;
REVOKE ALL ON SCHEMA insight FROM PUBLIC;
ALTER ROLE pbl_insight SET search_path = insight, public;

-- Neon: the pooled endpoint does not allow per-role search_path; use the direct (non-pooled) host in `database_host`.
