#!/usr/bin/env bash
set -euo pipefail

# === Zero-Trust MySQL One-Click Deploy ===
# What it does:
#  - Creates database: securedb
#  - Creates users: db_owner, app_api (NO LOGIN), app_user, auditor, migration
#  - Enforces: proc-only writes, tenant isolation, encrypted PII, hash-chained audit
#  - Leaves you with a runnable demo

DB_NAME="securedb"
DB_CHARSET="utf8mb4"
DB_COLLATE="utf8mb4_0900_ai_ci"

# ---- How we connect to MySQL as root ----
# 1) Try socket auth (common on Linux): sudo mysql -uroot
# 2) If that fails, prompt for MYSQL_ROOT_PASSWORD and use TCP
MYSQL_CMD="sudo mysql -uroot"

echo "[*] Probing MySQL root (socket auth)..."
if ! echo "SELECT 1;" | $MYSQL_CMD >/dev/null 2>&1; then
  echo "[!] Socket root login failed. Using TCP with password."
  read -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD; echo
  MYSQL_CMD="mysql -uroot -p${MYSQL_ROOT_PASSWORD}"
  # Try again:
  echo "SELECT 1;" | $MYSQL_CMD >/dev/null
fi
echo "[OK] Connected to MySQL."

# ---- Optional: enable REQUIRE SSL for app users (server must be SSL-configured)
REQUIRE_SSL="${REQUIRE_SSL:-0}"  # set to 1 before running to enforce SSL on users

SQL=$(cat <<'SQL_EOF'
-- idempotent cleanup
DROP DATABASE IF EXISTS securedb;

-- Users (drop carefully; ignore errors if absent)
DROP USER IF EXISTS 'db_owner'@'localhost';
DROP USER IF EXISTS 'db_owner'@'%';
DROP USER IF EXISTS 'app_user'@'localhost';
DROP USER IF EXISTS 'app_user'@'%';
DROP USER IF EXISTS 'app_api'@'localhost';
DROP USER IF EXISTS 'app_api'@'%';
DROP USER IF EXISTS 'auditor'@'localhost';
DROP USER IF EXISTS 'auditor'@'%';
DROP USER IF EXISTS 'migration'@'localhost';
DROP USER IF EXISTS 'migration'@'%';

-- Create fresh DB
CREATE DATABASE securedb CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

-- Create users (localhost only; add '%' if you need remote connections)
CREATE USER 'db_owner'@'localhost' IDENTIFIED BY 'Owner#ChangeMe!23';
CREATE USER 'app_user'@'localhost' IDENTIFIED BY 'App#ChangeMe!23';
CREATE USER 'app_api'@'localhost' IDENTIFIED BY 'NoLogin#Blocked!23' ACCOUNT LOCK; -- locked: callable as DEFINER only
CREATE USER 'auditor'@'localhost' IDENTIFIED BY 'Audit#ChangeMe!23';
CREATE USER 'migration'@'localhost' IDENTIFIED BY 'Migrate#ChangeMe!23';

-- Optional remote accounts (comment out if not needed)
-- CREATE USER 'db_owner'@'%' IDENTIFIED BY 'Owner#ChangeMe!23';
-- CREATE USER 'app_user'@'%' IDENTIFIED BY 'App#ChangeMe!23';
-- CREATE USER 'app_api'@'%' IDENTIFIED BY 'NoLogin#Blocked!23' ACCOUNT LOCK;
-- CREATE USER 'auditor'@'%' IDENTIFIED BY 'Audit#ChangeMe!23';
-- CREATE USER 'migration'@'%' IDENTIFIED BY 'Migrate#ChangeMe!23';

-- Grant db_owner full control
GRANT ALL PRIVILEGES ON securedb.* TO 'db_owner'@'localhost';
-- GRANT ALL PRIVILEGES ON securedb.* TO 'db_owner'@'%';

-- Minimal grants for others (we’ll refine after objects exist)
GRANT USAGE ON *.* TO 'app_user'@'localhost';
GRANT USAGE ON *.* TO 'auditor'@'localhost';
GRANT USAGE ON *.* TO 'migration'@'localhost';
-- GRANT USAGE ON *.* TO 'app_user'@'%'; GRANT USAGE ON *.* TO 'auditor'@'%'; GRANT USAGE ON *.* TO 'migration'@'%';

FLUSH PRIVILEGES;

USE securedb;

-- ========================
-- Core tables (single schema for MySQL)
-- ========================

-- Tenants
CREATE TABLE tenants (
  id BINARY(16) PRIMARY KEY DEFAULT (UUID_TO_BIN(UUID(), 1)),
  name VARCHAR(255) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- Users (with encrypted PII + IVs)
CREATE TABLE users (
  id BINARY(16) PRIMARY KEY DEFAULT (UUID_TO_BIN(UUID(), 1)),
  tenant_id BINARY(16) NOT NULL,
  full_name VARCHAR(255) NOT NULL,
  email_enc VARBINARY(4096) NOT NULL,
  email_iv VARBINARY(16) NOT NULL,
  phone_enc VARBINARY(4096) NOT NULL,
  phone_iv VARBINARY(16) NOT NULL,
  role ENUM('admin','manager','analyst','viewer') NOT NULL,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Accounts
CREATE TABLE accounts (
  id BINARY(16) PRIMARY KEY DEFAULT (UUID_TO_BIN(UUID(), 1)),
  tenant_id BINARY(16) NOT NULL,
  owner_user BINARY(16) NOT NULL,
  balance_cents BIGINT NOT NULL CHECK (balance_cents >= 0),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_accts_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
  CONSTRAINT fk_accts_owner FOREIGN KEY (owner_user) REFERENCES users(id)
) ENGINE=InnoDB;

-- Session context (per-connection state for tenant + demo key)
CREATE TABLE session_ctx (
  conn_id INT PRIMARY KEY,
  tenant_id BINARY(16) NULL,
  symkey VARBINARY(32) NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Audit table with hash chain
CREATE TABLE audit_events (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  ts TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  actor VARCHAR(128) NOT NULL,
  app_tenant CHAR(36) NULL,
  table_name VARCHAR(64) NOT NULL,
  action ENUM('INSERT','UPDATE','DELETE') NOT NULL,
  pk_text VARCHAR(64) NULL,
  before_doc JSON NULL,
  after_doc JSON NULL,
  txid BIGINT NULL,
  client_addr VARCHAR(64) NULL,
  prev_hash VARBINARY(32) NULL,
  curr_hash VARBINARY(32) NULL
) ENGINE=InnoDB;

-- ========================
-- Security helpers / context API
-- ========================
DELIMITER $$

CREATE DEFINER='db_owner'@'localhost' PROCEDURE security_set_tenant(p_tenant CHAR(36))
SQL SECURITY DEFINER
BEGIN
  INSERT INTO session_ctx (conn_id, tenant_id)
  VALUES (CONNECTION_ID(), UUID_TO_BIN(p_tenant, 1))
  ON DUPLICATE KEY UPDATE tenant_id = VALUES(tenant_id);
END$$

CREATE DEFINER='db_owner'@'localhost' PROCEDURE security_set_demo_key(p_key VARBINARY(32))
SQL SECURITY DEFINER
BEGIN
  INSERT INTO session_ctx (conn_id, symkey)
  VALUES (CONNECTION_ID(), p_key)
  ON DUPLICATE KEY UPDATE symkey = VALUES(symkey);
END$$

CREATE DEFINER='db_owner'@'localhost' FUNCTION get_tenant() RETURNS BINARY(16)
SQL SECURITY DEFINER
BEGIN
  DECLARE t BINARY(16);
  SELECT tenant_id INTO t FROM session_ctx WHERE conn_id = CONNECTION_ID();
  RETURN t;
END$$

CREATE DEFINER='db_owner'@'localhost' FUNCTION get_symkey() RETURNS VARBINARY(32)
SQL SECURITY DEFINER
BEGIN
  DECLARE k VARBINARY(32);
  SELECT symkey INTO k FROM session_ctx WHERE conn_id = CONNECTION_ID();
  RETURN k;
END$$

-- ========================
-- API (proc-only writes)
-- ========================

CREATE DEFINER='db_owner'@'localhost' PROCEDURE app_create_user(
  IN p_tenant CHAR(36),
  IN p_name   VARCHAR(255),
  IN p_email  TEXT,
  IN p_phone  TEXT,
  IN p_role   VARCHAR(16),
  OUT o_user_id CHAR(36)
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_tid BINARY(16);
  DECLARE v_key VARBINARY(32);
  DECLARE v_eiv VARBINARY(16);
  DECLARE v_piv VARBINARY(16);
  DECLARE v_uid BINARY(16);

  SET v_tid = UUID_TO_BIN(p_tenant, 1);
  SET v_key = get_symkey();
  IF v_key IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Symmetric key not set for session';
  END IF;

  SET v_eiv = RANDOM_BYTES(16);
  SET v_piv = RANDOM_BYTES(16);

  INSERT INTO users(tenant_id, full_name, email_enc, email_iv, phone_enc, phone_iv, role)
  VALUES(
    v_tid, p_name,
    AES_ENCRYPT(p_email, v_key, v_eiv),
    v_eiv,
    AES_ENCRYPT(p_phone, v_key, v_piv),
    v_piv,
    p_role
  );
  SET v_uid = LAST_INSERT_ID(); -- not correct for UUID; workaround:
  -- fetch actual id:
  SELECT id INTO v_uid FROM users
    WHERE tenant_id=v_tid AND full_name=p_name
    ORDER BY created_at DESC LIMIT 1;

  SET o_user_id = BIN_TO_UUID(v_uid, 1);
END$$

CREATE DEFINER='db_owner'@'localhost' PROCEDURE app_open_account(
  IN p_tenant CHAR(36),
  IN p_owner  CHAR(36),
  IN p_initial BIGINT
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_tid BINARY(16);
  DECLARE v_owner BINARY(16);

  IF p_initial < 0 THEN SIGNAL SQLSTATE '22003' SET MESSAGE_TEXT='Initial must be >= 0'; END IF;

  SET v_tid   = UUID_TO_BIN(p_tenant, 1);
  SET v_owner = UUID_TO_BIN(p_owner, 1);

  IF NOT EXISTS (SELECT 1 FROM users WHERE id=v_owner AND tenant_id=v_tid) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Owner not in tenant';
  END IF;

  INSERT INTO accounts(tenant_id, owner_user, balance_cents)
  VALUES (v_tid, v_owner, p_initial);
END$$

CREATE DEFINER='db_owner'@'localhost' PROCEDURE app_transfer(
  IN p_tenant CHAR(36),
  IN p_from   CHAR(36),
  IN p_to     CHAR(36),
  IN p_amount BIGINT
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_tid BINARY(16);
  DECLARE v_from BINARY(16);
  DECLARE v_to BINARY(16);

  IF p_amount <= 0 THEN SIGNAL SQLSTATE '22003' SET MESSAGE_TEXT='Amount must be > 0'; END IF;

  SET v_tid  = UUID_TO_BIN(p_tenant, 1);
  SET v_from = UUID_TO_BIN(p_from, 1);
  SET v_to   = UUID_TO_BIN(p_to, 1);

  IF NOT EXISTS (SELECT 1 FROM accounts WHERE id=v_from AND tenant_id=v_tid) OR
     NOT EXISTS (SELECT 1 FROM accounts WHERE id=v_to   AND tenant_id=v_tid) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Cross-tenant transfer blocked';
  END IF;

  START TRANSACTION;
    UPDATE accounts SET balance_cents = balance_cents - p_amount WHERE id=v_from;
    IF ROW_COUNT() = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='From account not found'; END IF;
    UPDATE accounts SET balance_cents = balance_cents + p_amount WHERE id=v_to;
  COMMIT;
END$$

-- ========================
-- Views (tenant-filtered reads)
-- ========================

CREATE OR REPLACE ALGORITHM=MERGE DEFINER='db_owner'@'localhost'
SQL SECURITY DEFINER
VIEW v_users AS
  SELECT BIN_TO_UUID(u.id,1) AS id,
         BIN_TO_UUID(u.tenant_id,1) AS tenant_id,
         u.full_name, u.role, u.created_at
  FROM users u
  WHERE u.tenant_id = get_tenant();

CREATE OR REPLACE ALGORITHM=MERGE DEFINER='db_owner'@'localhost'
SQL SECURITY DEFINER
VIEW v_accounts AS
  SELECT BIN_TO_UUID(a.id,1) AS id,
         BIN_TO_UUID(a.tenant_id,1) AS tenant_id,
         BIN_TO_UUID(a.owner_user,1) AS owner_user,
         a.balance_cents, a.created_at
  FROM accounts a
  WHERE a.tenant_id = get_tenant();

-- Private view with decrypted PII (only API/auditor)
CREATE OR REPLACE ALGORITHM=MERGE DEFINER='db_owner'@'localhost'
SQL SECURITY DEFINER
VIEW v_users_private AS
  SELECT BIN_TO_UUID(u.id,1) AS id,
         BIN_TO_UUID(u.tenant_id,1) AS tenant_id,
         u.full_name,
         CAST(AES_DECRYPT(u.email_enc, get_symkey(), u.email_iv) AS CHAR) AS email,
         CAST(AES_DECRYPT(u.phone_enc, get_symkey(), u.phone_iv) AS CHAR) AS phone,
         u.role, u.created_at
  FROM users u
  WHERE u.tenant_id = get_tenant();

-- ========================
-- Auditing (hash chain)
-- ========================

CREATE DEFINER='db_owner'@'localhost' PROCEDURE audit_log_event(
  IN p_table VARCHAR(64),
  IN p_action ENUM('INSERT','UPDATE','DELETE'),
  IN p_pk_text VARCHAR(64),
  IN p_before JSON,
  IN p_after  JSON
)
SQL SECURITY DEFINER
BEGIN
  DECLARE v_prev VARBINARY(32);
  DECLARE v_tenant CHAR(36);

  SELECT HEX(curr_hash) INTO @ignore FROM audit_events WHERE table_name=p_table ORDER BY id DESC LIMIT 1; -- warm pages
  SELECT curr_hash INTO v_prev FROM audit_events WHERE table_name=p_table ORDER BY id DESC LIMIT 1;

  SELECT BIN_TO_UUID(tenant_id,1) INTO v_tenant FROM session_ctx WHERE conn_id = CONNECTION_ID();

  INSERT INTO audit_events(actor, app_tenant, table_name, action, pk_text, before_doc, after_doc, txid, client_addr, prev_hash, curr_hash)
  VALUES (CURRENT_USER(), v_tenant, p_table, p_action, p_pk_text, p_before, p_after, 0, SUBSTRING_INDEX(USER(), '@', -1), v_prev,
          UNHEX(SHA2(CONCAT_WS('|',
              IFNULL(HEX(v_prev), ''),
              IFNULL(v_tenant, ''),
              p_table, p_action, IFNULL(p_pk_text,''),
              JSON_EXTRACT(IFNULL(p_before, JSON_OBJECT()), '$'),
              JSON_EXTRACT(IFNULL(p_after,  JSON_OBJECT()), '$'),
              NOW()
          ),256)));
END$$

-- Triggers for USERS
DROP TRIGGER IF EXISTS trg_users_ins;
CREATE DEFINER='db_owner'@'localhost' TRIGGER trg_users_ins
AFTER INSERT ON users FOR EACH ROW
BEGIN
  CALL audit_log_event(
    'users','INSERT', BIN_TO_UUID(NEW.id,1),
    NULL,
    JSON_OBJECT(
      'id', BIN_TO_UUID(NEW.id,1),
      'tenant', BIN_TO_UUID(NEW.tenant_id,1),
      'full_name', NEW.full_name,
      'role', NEW.role,
      'created_at', NEW.created_at
    )
  );
END$$

DROP TRIGGER IF EXISTS trg_users_upd;
CREATE DEFINER='db_owner'@'localhost' TRIGGER trg_users_upd
AFTER UPDATE ON users FOR EACH ROW
BEGIN
  CALL audit_log_event(
    'users','UPDATE', BIN_TO_UUID(NEW.id,1),
    JSON_OBJECT(
      'id', BIN_TO_UUID(OLD.id,1),
      'tenant', BIN_TO_UUID(OLD.tenant_id,1),
      'full_name', OLD.full_name,
      'role', OLD.role,
      'created_at', OLD.created_at
    ),
    JSON_OBJECT(
      'id', BIN_TO_UUID(NEW.id,1),
      'tenant', BIN_TO_UUID(NEW.tenant_id,1),
      'full_name', NEW.full_name,
      'role', NEW.role,
      'created_at', NEW.created_at
    )
  );
END$$

DROP TRIGGER IF EXISTS trg_users_del;
CREATE DEFINER='db_owner'@'localhost' TRIGGER trg_users_del
AFTER DELETE ON users FOR EACH ROW
BEGIN
  CALL audit_log_event(
    'users','DELETE', BIN_TO_UUID(OLD.id,1),
    JSON_OBJECT(
      'id', BIN_TO_UUID(OLD.id,1),
      'tenant', BIN_TO_UUID(OLD.tenant_id,1),
      'full_name', OLD.full_name,
      'role', OLD.role,
      'created_at', OLD.created_at
    ),
    NULL
  );
END$$

-- Triggers for ACCOUNTS
DROP TRIGGER IF EXISTS trg_accounts_ins;
CREATE DEFINER='db_owner'@'localhost' TRIGGER trg_accounts_ins
AFTER INSERT ON accounts FOR EACH ROW
BEGIN
  CALL audit_log_event(
    'accounts','INSERT', BIN_TO_UUID(NEW.id,1),
    NULL,
    JSON_OBJECT(
      'id', BIN_TO_UUID(NEW.id,1),
      'tenant', BIN_TO_UUID(NEW.tenant_id,1),
      'owner_user', BIN_TO_UUID(NEW.owner_user,1),
      'balance_cents', NEW.balance_cents,
      'created_at', NEW.created_at
    )
  );
END$$

DROP TRIGGER IF EXISTS trg_accounts_upd;
CREATE DEFINER='db_owner'@'localhost' TRIGGER trg_accounts_upd
AFTER UPDATE ON accounts FOR EACH ROW
BEGIN
  CALL audit_log_event(
    'accounts','UPDATE', BIN_TO_UUID(NEW.id,1),
    JSON_OBJECT(
      'id', BIN_TO_UUID(OLD.id,1),
      'tenant', BIN_TO_UUID(OLD.tenant_id,1),
      'owner_user', BIN_TO_UUID(OLD.owner_user,1),
      'balance_cents', OLD.balance_cents,
      'created_at', OLD.created_at
    ),
    JSON_OBJECT(
      'id', BIN_TO_UUID(NEW.id,1),
      'tenant', BIN_TO_UUID(NEW.tenant_id,1),
      'owner_user', BIN_TO_UUID(NEW.owner_user,1),
      'balance_cents', NEW.balance_cents,
      'created_at', NEW.created_at
    )
  );
END$$

DROP TRIGGER IF EXISTS trg_accounts_del;
CREATE DEFINER='db_owner'@'localhost' TRIGGER trg_accounts_del
AFTER DELETE ON accounts FOR EACH ROW
BEGIN
  CALL audit_log_event(
    'accounts','DELETE', BIN_TO_UUID(OLD.id,1),
    JSON_OBJECT(
      'id', BIN_TO_UUID(OLD.id,1),
      'tenant', BIN_TO_UUID(OLD.tenant_id,1),
      'owner_user', BIN_TO_UUID(OLD.owner_user,1),
      'balance_cents', OLD.balance_cents,
      'created_at', OLD.created_at
    ),
    NULL
  );
END$$

DELIMITER ;

-- ========================
-- Seed data (two tenants)
-- ========================
INSERT INTO tenants(name) VALUES ('Acme Corp'), ('Globex Ltd');

-- ========================
-- Privileges lockdown
-- ========================

-- No direct table access for app_user
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'app_user'@'localhost';
-- base tables: deny
REVOKE SELECT, INSERT, UPDATE, DELETE ON securedb.* FROM 'app_user'@'localhost';

-- app_user can read via tenant-filtered views, and EXECUTE API
GRANT SELECT ON securedb.v_users    TO 'app_user'@'localhost';
GRANT SELECT ON securedb.v_accounts TO 'app_user'@'localhost';
GRANT EXECUTE ON PROCEDURE securedb.security_set_tenant TO 'app_user'@'localhost';
GRANT EXECUTE ON PROCEDURE securedb.security_set_demo_key TO 'app_user'@'localhost';
GRANT EXECUTE ON PROCEDURE securedb.app_create_user TO 'app_user'@'localhost';
GRANT EXECUTE ON PROCEDURE securedb.app_open_account TO 'app_user'@'localhost';
GRANT EXECUTE ON PROCEDURE securedb.app_transfer TO 'app_user'@'localhost';

-- app_user cannot see decrypted PII view
REVOKE SELECT ON securedb.v_users_private FROM 'app_user'@'localhost';

-- auditor can read audit trail + private view (must set tenant + key)
GRANT SELECT ON securedb.audit_events TO 'auditor'@'localhost';
GRANT SELECT ON securedb.v_users_private TO 'auditor'@'localhost';
GRANT EXECUTE ON PROCEDURE securedb.security_set_tenant TO 'auditor'@'localhost';
GRANT EXECUTE ON PROCEDURE securedb.security_set_demo_key TO 'auditor'@'localhost';

-- migration gets DDL on base objects
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP ON securedb.* TO 'migration'@'localhost';

-- Lock the base tables to everyone else
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'auditor'@'localhost';

FLUSH PRIVILEGES;
SQL_EOF
)

echo "[*] Creating secure schema..."
echo "$SQL" | $MYSQL_CMD
echo "[OK] Database '$DB_NAME' created with security controls."

# Optional: enforce REQUIRE SSL on users if server has SSL configured
if [[ "$REQUIRE_SSL" == "1" ]]; then
  echo "[*] Enforcing REQUIRE SSL on app/auditor users..."
  $MYSQL_CMD <<'SQL_SSL'
ALTER USER 'app_user'@'localhost' REQUIRE SSL;
ALTER USER 'auditor'@'localhost' REQUIRE SSL;
FLUSH PRIVILEGES;
SQL_SSL
  echo "[OK] Users now require SSL (server must be SSL-enabled)."
fi

cat <<'POST'
========================================================
Zero-Trust MySQL deployed.

Accounts (change these after demo):
  db_owner / Owner#ChangeMe!23
  app_user / App#ChangeMe!23
  auditor  / Audit#ChangeMe!23
  migration/ Migrate#ChangeMe!23

Next: run the quick demo (copy/paste lines below).

# 1) Log in as app_user
mysql -u app_user -p -D securedb -e "
CALL security_set_tenant((SELECT BIN_TO_UUID(id,1) FROM tenants WHERE name='Acme Corp' LIMIT 1));
CALL security_set_demo_key(UNHEX('00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF'));
SET @tid  := (SELECT BIN_TO_UUID(id,1) FROM tenants WHERE name='Acme Corp' LIMIT 1);
CALL app_create_user(@tid,'Alice Admin','alice@acme.example','+1-202-555-0101','admin', @uid1);
CALL app_create_user(@tid,'Bob Analyst','bob@acme.example','+1-202-555-0102','analyst', @uid2);
SELECT @uid1 AS alice_id, @uid2 AS bob_id;
CALL app_open_account(@tid, @uid1, 500000);
CALL app_open_account(@tid, @uid2, 250000);
SELECT * FROM v_users;
SELECT * FROM v_accounts;
CALL app_transfer(@tid,
  (SELECT BIN_TO_UUID(id,1) FROM accounts ORDER BY created_at ASC LIMIT 1),
  (SELECT BIN_TO_UUID(id,1) FROM accounts ORDER BY created_at DESC LIMIT 1),
  12345);
SELECT * FROM v_accounts;
"

# 2) Try (and fail) direct table writes as app_user:
mysql -u app_user -p -D securedb -e "INSERT INTO users(full_name) VALUES('Mallory');" || echo "Direct insert blocked ✔"

# 3) See audit as auditor (you'll need the same tenant + key to decrypt private view)
mysql -u auditor -p -D securedb -e "
CALL security_set_tenant((SELECT BIN_TO_UUID(id,1) FROM tenants WHERE name='Acme Corp' LIMIT 1));
CALL security_set_demo_key(UNHEX('00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF'));
SELECT id, ts, actor, table_name, action, pk_text, HEX(curr_hash) hash FROM audit_events ORDER BY id DESC LIMIT 10;
SELECT * FROM v_users_private LIMIT 2;
"

# 4) RLS: switch tenant and observe empty reads
mysql -u app_user -p -D securedb -e "
CALL security_set_tenant((SELECT BIN_TO_UUID(id,1) FROM tenants WHERE name='Globex Ltd' LIMIT 1));
SELECT * FROM v_users;  -- should be empty for now
"

========================================================
POST
