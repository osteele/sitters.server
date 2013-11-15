CREATE TYPE trigger_operation AS ENUM ('DELETE', 'INSERT', 'UPDATE');

CREATE TABLE IF NOT EXISTS change_log (
  operation         trigger_operation NOT NULL,
  table_name        text      NOT NULL,
  entity_id         integer   NOT NULL,
  timestamp         timestamp NOT NULL
);

-- adapted from http://www.postgresql.org/docs/8.1/static/plpgsql-trigger.html
CREATE OR REPLACE FUNCTION log_row_change() RETURNS TRIGGER AS $log_row_change$
  BEGIN
    IF (TG_OP = 'DELETE') THEN
      INSERT INTO change_log SELECT 'DELETE', TG_RELNAME, OLD.id, now();
      RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
      INSERT INTO change_log SELECT 'UPDATE', TG_RELNAME, NEW.id, now();
      RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
      INSERT INTO change_log SELECT 'INSERT', TG_RELNAME, NEW.id, now();
      RETURN NEW;
    END IF;
    RETURN NULL; -- result is ignored since this is an AFTER trigger
  END;
$log_row_change$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS log_row_change ON accounts;
CREATE TRIGGER log_row_change
AFTER INSERT OR UPDATE OR DELETE
ON accounts
  FOR EACH ROW EXECUTE PROCEDURE log_row_change();

DROP TRIGGER IF EXISTS log_row_change ON families;
CREATE TRIGGER log_row_change
AFTER INSERT OR UPDATE OR DELETE
ON families
  FOR EACH ROW EXECUTE PROCEDURE log_row_change();

DROP TRIGGER IF EXISTS log_row_change ON sitters;
CREATE TRIGGER log_row_change
AFTER INSERT OR UPDATE OR DELETE
ON sitters
  FOR EACH ROW EXECUTE PROCEDURE log_row_change();

DROP TRIGGER IF EXISTS log_row_change ON users;
CREATE TRIGGER log_row_change
AFTER INSERT OR UPDATE OR DELETE
ON users
  FOR EACH ROW EXECUTE PROCEDURE log_row_change();
