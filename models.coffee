Schema = require('jugglingdb').Schema
schema = new Schema('postgres', {database: 'localhost', username: 'sitters', password: 'sitters', database: 'sitters'})

Account = schema.define 'accounts',
  provider: String
  user_id: String

Family = schema.define 'families',
  sitter_ids: []

Sitter = schema.define 'sitters',
  data: Schema.JSON

User = schema.define 'users',
  displayName: String
  email: String

User.hasMany Account
Family.hasMany 'parents', model: User

schema.isActual (err, actual) ->
  schema.autoupdate() unless actual

module.exports = {
  Account
  Family
  Sitter
  User
}
