require('dotenv').load()

config = do ->
  DATABASE_URL = process.env.DATABASE_URL
  match = DATABASE_URL.match(RegExp('^postgres://(.+?):(.+?)@(.+?)(?::([0-9]+))?/(.+)$'))
  throw "DATABASE_URL not a known syntax: #{DATABASE_URL}" unless match
  [username, password, host, port, database] = match.slice(1)
  port = Number(port ? 5432)
  {username, password, host, port, database}

Schema = require('jugglingdb').Schema
schema = new Schema('postgres', config)

Account = schema.define 'accounts',
  provider_name: {type: String, index: true}
  provider_user_id: {type: String, index: true}

Family = schema.define 'families',
  sitter_ids: Schema.JSON # INTEGER[]

Sitter = schema.define 'sitters',
  data: Schema.JSON

User = schema.define 'users',
  displayName: String
  email: String

User.hasMany Account, foreignKey: 'user_id'
Family.hasMany 'parents', model: User, foreignKey: 'family_id'

schema.isActual (err, actual) ->
  schema.autoupdate() unless actual

module.exports = {
  Account
  Family
  Sitter
  User
  schema
}
