# Define the database models and connection.

require('dotenv').load()
_ = require 'underscore'
Q = require 'q'


#
# Configure Logging
# --
#

winston = require 'winston'
if process.env.NODE_ENV == 'production'
  # In production, log sql to stdout so that it's routed to consolidated logging
  loggerOptions = {console:{colorize:true, label:'sql'}}
else
  # In development, route sql to a file so that it's out of the way but available via tail -f.
  loggerOptions = {console:{silent:true}, file:{filename:__dirname + '/../logs/sql.log', json:false}}
logger = winston.loggers.add 'sql', loggerOptions

# This is exported so that ./bin/print-generated-schema can override it
exports.logger = (msg) -> logger.info msg


#
# Database Connection
# --
#

Sequelize = require('sequelize-postgres').sequelize
sequelize = new Sequelize process.env.DATABASE_URL,
  dialect: 'postgres'
  define: {underscored:true}
  logging: (msg) -> exports.logger msg
  pool: { maxConnections:5, maxIdleTime:30 }


#
# Define Models
# --
#

# An Account holds the third-party information by which a user authenticates.
# In the future, a User may have several Accounts, if they connect to multiple providers
# or create an email account and then connect it.
Account = sequelize.define 'accounts',
  provider_name: {type: Sequelize.STRING, index: true}
  provider_user_id: {type: Sequelize.STRING, index: true}
,
  getterMethods:
    firebaseKey: -> [@.provider_name, @.provider_user_id].join('-')

Device = sequelize.define 'devices',
  token: {type: Sequelize.STRING(64), index:true, unique:true}
  uuid: {type:Sequelize.STRING(36), index:true, unique:true}

Family = sequelize.define 'families',
  sitter_ids: Sequelize.ARRAY(Sequelize.INTEGER)

PaymentCustomer = sequelize.define 'payment_customers',
  stripe_customer_id: Sequelize.STRING
  card_info:
    type: Sequelize.TEXT
    get: -> JSON.parse(JSON.parse(@getDataValue('card_info')))
    set: (data) -> @setDataValue 'card_info', JSON.stringify(data)

# The sitter is really sitter profile information, and is associated to a User.
Sitter = sequelize.define 'sitters',
  data:
    type: Sequelize.TEXT
    get: -> JSON.parse(JSON.parse(@getDataValue('data')))
    set: (data) -> @setDataValue 'data', JSON.stringify(data)
  is_simulated: {type:Sequelize.BOOLEAN, allowNull:false, defaultValue:false}
,
  getterMethods:
    firstName: -> @.data.name.split(/\s/).shift()

User = sequelize.define 'users',
  displayName: Sequelize.STRING
  email: {type: Sequelize.STRING, index: true, unique: true}
  phone: {type: Sequelize.STRING(15), index: true, unique: true}


#
# Module Associations
# --
#

Account.belongsTo User
Family.hasMany User
PaymentCustomer.belongsTo User
Sitter.belongsTo User
User.hasMany Account
User.hasMany Device
User.belongsTo Family
User.hasOne PaymentCustomer
User.hasOne Sitter

#
# Custom Finders
# --
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
# Exports
# --
#

module.exports = _.extend exports, {
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
