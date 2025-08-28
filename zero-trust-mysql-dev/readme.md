A **tamper-evident, one-click deploy** for a **MySQL 8** instance on a Google Cloud VM (Ubuntu/Debian/CentOS). Ensure MySQL is installed and running).

It sets up:

* **Proc-only writes** (app users can’t touch tables directly).
* **Tenant isolation** via a per-connection context (no cross-tenant reads).
* **Encrypted PII** using per-row IVs (AES\_ENCRYPT/AES\_DECRYPT) with a session key that’s **not stored in the DB**.
* **Immutable audit log** with **hash chaining** (tamper-evident).
* **Least privilege**: revoked direct DML/SELECT on base tables for app users; read via filtered views only.
* Optional **REQUIRE SSL** for app/auditor users (if you enable server SSL—instructions included).

---

For quick demo (copy/paste lines below).

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

---

## What this proves in the demo

1. **DBA ≠ Data**: Even superusers can’t decrypt PII without the session key (we never store the key in DB; we simulate KMS with a session setter).
2. **Tenant fences**: Reads are only through `v_users` / `v_accounts`, filtered by the tenant bound to your connection (`get_tenant()` via `session_ctx`).
3. **Proc-only writes**: All inserts/updates happen through `app_*` stored procedures with checks; direct table DML fails for `app_user`.
4. **Tamper-evident audit**: `audit_events` keeps a **SHA-256 hash chain** per table. Insert/Update/Delete triggers call `audit_log_event`—any hole breaks the chain.
5. **Optional SSL**: Flip `REQUIRE_SSL=1` before running, and (if your MySQL server is SSL-enabled) app/auditor users must use TLS.

---

## Hard truth

* On any RDBMS, **root on the box** or someone who can replace binaries can ultimately see data in memory. That’s why real “DBA-proof” requires **client-side encryption + external KMS/HSM**.
* This setup models that boundary: the **key never lives in the DB** (we simulate session-provided key), and **app\_user** cannot bypass the API or tenant fences.

If you want, I can also give you a **tiny Python client snippet** that does **AES-GCM client-side** before hitting MySQL—so even a compromised DB sees only ciphertext.
