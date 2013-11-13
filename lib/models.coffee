require('dotenv').load()
_ = require 'underscore'
Q = require 'q'
winston = require 'winston'

winston.loggers.add 'database',
  console:
    colorize: 'true'
    label: 'database'
    silent: true
  file:
    filename: __dirname + '/../logs/database.log'
    json: false

Sequelize = require('sequelize-postgres').sequelize
sequelize = new Sequelize process.env.DATABASE_URL,
  dialect: 'postgres'
  define: {underscored:true}
  logging: do ->
    logger = winston.loggers.get('database')
    (msg) -> logger.info msg

Account = sequelize.define 'accounts',
  provider_name: {type: Sequelize.STRING, index: true}
  provider_user_id: {type: Sequelize.STRING, index: true}

Device = sequelize.define 'devices',
  token: {type: Sequelize.STRING, index: true, unique: true}

Family = sequelize.define 'families',
  sitter_ids: Sequelize.ARRAY(Sequelize.INTEGER)

Sitter = sequelize.define 'sitters', {
  data:
    type: Sequelize.TEXT
    get: -> JSON.parse(JSON.parse(@getDataValue('data')))
    set: (data) -> @setDataValue 'data', JSON.stringify(data)
}, {
  getterMethods:
    firstName: -> @.data.name.split(/\s/).shift()
}

User = sequelize.define 'users',
  displayName: Sequelize.STRING
  email: {type: Sequelize.STRING, index: true, unique: true}

Family.hasMany User
User.hasMany Account
User.hasMany Device
# migration.addIndex('Person', ['firstname', 'lastname'])

SelectDeviceTokensForAccountKeySQL = """
SELECT token
FROM devices
JOIN users ON users.id=devices.user_id
JOIN accounts ON accounts.user_id=users.id
WHERE provider_name=:provider_name and provider_user_id=:provider_user_id;"""

SelectAccountUserFamilySQL = """
SELECT families.id, families.created_at, families.sitter_ids
FROM families
JOIN users ON families.id=family_id
JOIN accounts ON users.id=user_id
WHERE provider_name=:provider_name and provider_user_id=:provider_user_id;"""

accountKeyDeviceTokensP = (accountKey) ->
  [provider_name, provider_user_id] = accountKey.split('/', 2)
  sequelize.query(SelectDeviceTokensForAccountKeySQL, null, {raw:true}, {provider_name, provider_user_id}).then (rows) ->
    Q (token for {token} in rows)

accountKeyUserFamilyP = (accountKey) ->
  [provider_name, provider_user_id] = accountKey.split('/', 2)
  sequelize.query(SelectAccountUserFamilySQL, Family, {}, {provider_name, provider_user_id}).then (rows) ->
    Q rows[0]

sequelize.sync()

module.exports = {
  Account
  Device
  Family
  Sitter
  User
  accountKeyDeviceTokensP
  accountKeyUserFamilyP
  sequelize
}
