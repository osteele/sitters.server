-- The down migration depends on being able to find the DROP TRIGGER statements.

DROP TRIGGER IF EXISTS log_row_change ON accounts;
CREATE TRIGGER log_row_change
AFTER INSERT OR UPDATE OR DELETE
ON accounts
  FOR EACH ROW EXECUTE PROCEDURE log_row_change();

DROP TRIGGER IF EXISTS log_row_change ON payment_customers;
CREATE TRIGGER log_row_change
AFTER INSERT OR UPDATE OR DELETE
ON payment_customers
  FOR EACH ROW EXECUTE PROCEDURE log_row_change();

DROP TRIGGER IF EXISTS log_row_change ON families;
CREATE TRIGGER log_row_change
AFTER INSERT OR UPDATE OR DELETE
ON families
  FOR EACH ROW EXECUTE PROCEDURE log_row_change();

DROP TRIGGER IF EXISTS log_row_change ON user_profiles;
CREATE TRIGGER log_row_change
AFTER INSERT OR UPDATE OR DELETE
ON user_profiles
  FOR EACH ROW EXECUTE PROCEDURE log_row_change();

DROP TRIGGER IF EXISTS log_row_change ON users;
CREATE TRIGGER log_row_change
AFTER INSERT OR UPDATE OR DELETE
ON users
  FOR EACH ROW EXECUTE PROCEDURE log_row_change();
