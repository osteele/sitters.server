fs = require 'fs'
async = require 'async'

exports.up = (db, done) ->
  sql = fs.readFileSync(__dirname + '/create-changelog.sql', 'utf-8')
  db.runSql sql, done

exports.down = (db, done) ->
  async.series [
    db.dropTable.bind db, 'change_log'
    db.runSql.bind db, 'DROP TYPE IF EXISTS trigger_operation'
  ], done
