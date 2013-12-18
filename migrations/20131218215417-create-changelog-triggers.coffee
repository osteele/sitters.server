fs = require 'fs'
async = require 'async'

DefineTriggersSql = fs.readFileSync(__dirname + '/create-changelog-triggers.sql', 'utf-8')

exports.up = (db, done) ->
  db.runSql DefineTriggersSql, done

exports.down = (db, done) ->
  statements = DefineTriggersSql.replace(/--.*\n/g, '').match(/^DROP TRIGGER\s[^;]*;/mg)
  async.each statements, db.runSql.bind(db), done
