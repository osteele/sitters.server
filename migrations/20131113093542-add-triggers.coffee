fs = require 'fs'

exports.up = (migration, DataTypes, done) ->
  triggersSQL = fs.readFileSync(__dirname + '/../config/triggers.sql', 'utf-8')
  migration.migrator.sequelize.query(triggersSQL).done done

exports.down = (migration, DataTypes, done) ->
  done()
