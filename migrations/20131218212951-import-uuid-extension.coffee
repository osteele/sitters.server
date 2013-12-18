exports.up = (db, done) ->
  db.runSql 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp";', done

exports.down = (db, done) ->
  done()


