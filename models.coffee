require('dotenv')().load()

config = do ->
  match = process.env.DATABASE_URL.match(RegExp('^postgres://(.+?):(.+?)@(.+?)/(.+)$'))
  throw "DATABASE_URL not a known syntax: #{process.env.DATABASE_URL}" unless match
  [username, password, hostname, database] = match.slice(1)
  {username, password, hostname, database}

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
