{sequelize} = require '../app/lib/models'

exports.up = (db, done) ->
  sequelize.sync(force:true).then -> done()

exports.down = (db, done) ->
  sequelize.drop().then -> done()
