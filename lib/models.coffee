require('dotenv').load()
_ = require 'underscore'
Q = require 'q'


#
# Logging
#

winston = require 'winston'
loggerOptions = {console: {colorize:true, label:'sql'}}
if process.env.NODE_ENV != 'production'
  loggerOptions = {console: {silent:true}, file: {filename:__dirname + '/../logs/sql.log', json:false}}
logger = winston.loggers.add 'sql', loggerOptions


#
# Database Connection
#

Sequelize = require('sequelize-postgres').sequelize
sequelize = new Sequelize process.env.DATABASE_URL,
  dialect: 'postgres'
  define: {underscored:true}
  logging: (msg) -> logger.info msg
  pool: { maxConnections: 5, maxIdleTime: 30 }


#
# Models
#

Account = sequelize.define 'accounts', {
  provider_name: {type: Sequelize.STRING, index: true}
  provider_user_id: {type: Sequelize.STRING, index: true}
}, {
  getterMethods:
    firebaseKey: -> [@.provider_name, @.provider_user_id].join('-')
}

Device = sequelize.define 'devices',
  token: {type: Sequelize.STRING, index: true, unique: true}

Family = sequelize.define 'families',
  sitter_ids: Sequelize.ARRAY(Sequelize.INTEGER)

PaymentCustomer = sequelize.define 'payment_customers',
  stripe_customer_id: Sequelize.STRING
  card_info:
    type: Sequelize.TEXT
    get: -> JSON.parse(JSON.parse(@getDataValue('card_info')))
    set: (data) -> @setDataValue 'card_info', JSON.stringify(data)

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


#
# Associations
#

Account.belongsTo User
Family.hasMany User
PaymentCustomer.belongsTo User
User.hasMany Account
User.belongsTo Family
User.hasOne PaymentCustomer
User.hasMany Device


sequelize.sync()


#
# Custom Finders
#

SelectUserByAccountKeySQL = """
SELECT
  users.*
FROM
  users
JOIN
  accounts ON users.id=accounts.user_id
WHERE provider_name=:provider_name
  AND provider_user_id=:provider_user_id
LIMIT 1
"""

User.findByAccountKey = (accountKey) ->
  [provider_name, provider_user_id] = accountKey.split('-', 2)
  sequelize.query(SelectUserByAccountKeySQL, User, {}, {provider_name, provider_user_id}).then (rows) ->
    Q rows[0]

SelectDeviceTokensForAccountKeySQL = """
SELECT
  token
FROM
  devices
JOIN
  users ON users.id=devices.user_id
JOIN
  accounts ON accounts.user_id=users.id
WHERE provider_name=:provider_name
  AND provider_user_id=:provider_user_id;
"""

accountKeyDeviceTokensP = (accountKey) ->
  [provider_name, provider_user_id] = accountKey.split('-', 2)
  sequelize.query(SelectDeviceTokensForAccountKeySQL, null, {raw:true}, {provider_name, provider_user_id}).then (rows) ->
    Q (token for {token} in rows)

updateUserSitterListP = (user, fn) ->
  user.getFamily().then (family) ->
    return unless family
    sitter_ids = fn(family.sitter_ids)
    return Q(false) unless sitter_ids
    sitter_ids = '{}' if sitter_ids.length == 0
    family.updateAttributes({sitter_ids}).then ->
      Q true


#
# Export
#

module.exports = {
  # Connection Instance
  sequelize

  # Models
  Account
  Device
  Family
  PaymentCustomer
  Sitter
  User

  # Finders
  accountKeyDeviceTokensP
  updateUserSitterListP
}
