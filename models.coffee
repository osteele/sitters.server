Schema = require('jugglingdb').Schema
schema = new Schema('postgres', {database: 'localhost', username: 'sitters', password: 'sitters', database: 'sitters'})

Account = schema.define 'accounts',
  provider_name: {type: String, index: true}
  provider_user_id: {type: String, index: true}

Family = schema.define 'families',
  sitter_ids: Schema.JSON #[Number]

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
