# Define the database models and connection.

require('dotenv').load()
_ = require 'underscore'
Q = require 'q'


#
# Configure Logging
# --

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

Sequelize = require('sequelize-postgres').sequelize
sequelize = new Sequelize process.env.DATABASE_URL,
  dialect: 'postgres'
  define: {underscored:true}
  logging: (msg) -> exports.logger msg
  omitNull: true
  pool: { maxConnections:5, maxIdleTime:30 }

sequelize.execute = (string, parameters={}) ->
  sequelize.query string, null, {raw:true}, parameters


#
# Define Models
# --

# An Account holds the third-party information by which a user authenticates.
# In the future, a User may have several Accounts, if they connect to multiple providers
# or create an email account and then connect it.
Account = sequelize.define 'accounts',
  provider_name: {type:Sequelize.STRING(20), index:true, allowNull:false}
  provider_user_id: {type:Sequelize.STRING(64), index:true, allowNull:false}
,
  getterMethods:
    authKey: -> [@.provider_name, @.provider_user_id].join('-')
    firebaseKey: -> [@.provider_name, @.provider_user_id].join('-')

Device = sequelize.define 'devices',
  # `token` is the APNS token
  token: {type: Sequelize.STRING(64), index:true, unique:true}
  # `uuid` is the vendor UUID, and is used as the natural key, even though there
  # is also an `id` for foreign references and in case this changes.
  uuid: {type:Sequelize.STRING(36), index:true, unique:true}

Family = sequelize.define 'families',
  sitter_ids: Sequelize.ARRAY(Sequelize.INTEGER)

Invitation = sequelize.define 'invitations',
  # one of: 'parentInvitesSitterToFamily'
  type: {type:Sequelize.STRING(40), index:true, allowNull:false}
  # one of 'open' | 'accepted' | 'declined'
  status: {type:Sequelize.STRING(10), index:true}

PaymentCustomer = sequelize.define 'payment_customers',
  stripe_customer_id: Sequelize.STRING
  card_info:
    type: Sequelize.TEXT
    get: -> JSON.parse(JSON.parse(@getDataValue('card_info')))
    set: (data) -> @setDataValue 'card_info', JSON.stringify(data)

# The sitter is really sitter profile information, and is associated to a User.
SitterProfile = sequelize.define 'sitter_profiles',
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
  # For now, each user has a single email and phone. Move these to an association if this changes.
  email: {type:Sequelize.STRING, index:true, unique:true}
  phone: {type:Sequelize.STRING(15), index:true, unique:true}


#
# Associations
# --

Account
  .belongsTo(User)

Family
  .hasMany(User)

# Invitation
#   .belongsTo(User, as:'Initiator', foreignKey:'initiator_id')
#   .belongsTo(User, as:'Recipient', foreignKey:'recipient_id')

PaymentCustomer
  .belongsTo(User)

SitterProfile
  .belongsTo(User)

User
  .hasMany(Account)
  .hasMany(Device)
  .hasMany(Invitation, as:'Initiator', foreignKey:'initiator_id')
  .hasMany(Invitation, as:'Recipient', foreignKey:'recipient_id')
  .belongsTo(Family)
  .hasOne(PaymentCustomer)
  .hasOne(SitterProfile)


#
# Custom Finders
# --

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

module.exports = _.extend exports, {
  # Connection Instance
  sequelize

  # Models
  Account
  Device
  Family
  Invitation
  PaymentCustomer
  SitterProfile
  User

  # Finders
  updateUserSitterListP
}
