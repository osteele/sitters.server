util = require 'util'

_ = require 'underscore'
Q = require 'q'
moment = require 'moment'
winston = require 'winston'
Firebase = require 'firebase'

_(global).extend require('./lib/models')
_(global).extend require('./lib/push')

loggingOptions = {timestamp: true}
loggingOptions = {colorize: true, timestamp: -> moment().format('H:MM:ss')} if process.env.ENVIRONMENT == 'development'

logger = winston
logger.remove winston.transports.Console
logger.add winston.transports.Console, loggingOptions

DefaultSitterConfirmationDelay = 20 * 1000

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
requestsFB = rootFB.child('request')
messagesFB = rootFB.child('message')
familyFB = rootFB.child('family')
accountFB = rootFB.child('account')

logger.info "Polling #{requestsFB}"
requestsFB.on 'child_added', (snapshot) ->
  key = snapshot.name()
  message = snapshot.val()
  {accountKey, requestType, parameters} = message
  logger.info "Processing request #{requestType} from #{accountKey} with #{JSON.stringify(parameters).replace(/"(\w+)":/g, '$1:')}"
  try
    handleRequestFrom accountKey, requestType, parameters
  # catch err
    # logger.error err
  finally
    requestsFB.child(key).remove()

handleRequestFrom = (accountKey, requestType, parameters) ->
  handler = handlers[requestType]
  unless handler
    logger.error "Unknown request type #{requestType}"
    return
  promise = handler(accountKey, parameters)
  promise.done()

# Message is expected to have:
#   messageType: String -- client keys behavior off of this
#   messageTitle: String -- UIAlert title
#   messageText: String -- UIAlert text; also, push notification text
#   parameters: Hash -- client interprets message against this
sendMessageTo = (accountKey, message) ->
  logger.info "Send -> #{accountKey}:", message
  firebaseMessageId = messagesFB.child(accountKey).push message
  # logger.info "firebaseMessageId = #{firebaseMessageId}"
  [provider_name, provider_user_id] = accountKey.split('/', 2)
  sequelize.query(SelectDeviceTokenFromAccountKeySQL, null, {raw:true}, {provider_name, provider_user_id}).then (rows) ->
    rows.forEach ({token}) ->
      logger.info "  Push #{message.messageType} -> #{token}"
      pushMessageTo token, alert: message.messageText, payload: message

SelectDeviceTokenFromAccountKeySQL = """
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

updateSitterListP = (accountKey, fn) ->
  [provider_name, provider_user_id] = accountKey.split('/', 2)
  sequelize.query(SelectAccountUserFamilySQL, Family, {}, {provider_name, provider_user_id}).then (rows) ->
    family = rows[0]
    return unless family
    sitter_ids = family.sitter_ids
    sitter_ids = fn(sitter_ids)
    return Q(false) unless sitter_ids
    logger.info "Update sitter_ids <-", sitter_ids
    family.updateAttributes({sitter_ids}).then ->
      logger.info "Updated sitter_ids <-", sitter_ids
      familyFB.child(String(family.id)).child('sitter_ids').set sitter_ids
      Q(true)

handlers =
  addSitter: (accountKey, {sitterId, delay}) ->
    delay ?= DefaultAddSitterDelay
    Q.delay(delay * 1000).then(-> updateSitterListP(accountKey, (sitter_ids) ->
      logger.info "Adding sitter", sitterId, " to ", sitter_ids
      return if sitterId in sitter_ids
      return sitter_ids.concat([sitterId])
    )).then((modified) ->
      logger.info "Sitter was already added" unless modified
      return unless modified
      Sitter.find(sitterId)
    ).then((sitter) ->
      return unless sitter
      logger.info "Sending message add sitter #{sitter.id}"
      logger.info JSON.parse(sitter.data), typeof JSON.parse(sitter.data)
      sitterFirstName = JSON.parse(sitter.data).name.split(/\s/).shift()
      logger.info sitterFirstName
      sendMessageTo accountKey,
        messageType: 'sitterAcceptedConnection'
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitterFirstName} has accepted your request. We’ve added her to your Seven Sitters."
        parameters: {sitterId: sitterId}
    )

  registerDeviceToken: (accountKey, {token}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    accountP = Account.find where: {provider_name, provider_user_id}
    deviceP = Device.find where: {token}
    Q.all([accountP, deviceP]).spread((account, device) ->
      logger.info "Register #{token} for device=#{device} account=#{account}"
      return if device and account.user_id == device.user_id
      if device
        logger.info "Update device #{device}"
        device.updateAttributes user_id: account.user_id
      else
        logger.info "Create device"
        Device.create {token, user_id: account.user_id}
    )

  registerUser: (accountKey, {displayName, email}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    accountP = Account.findOrCreate({provider_name, provider_user_id})
    userP = User.findOrCreate({email}, {displayName})
    Q.all([accountP, userP]).spread (account, user) ->
      logger.info "Found account key=#{accountKey}" if account
      # return if user.hasAccount(account)
      Q.all [
        account.updateAttributes user_id: user.id
        user.updateAttributes {displayName} #unless user.displayName == displayName,
        Family.find(user.family_id).then (family) ->
          return if family
          Family.create({sitter_ids: '{}'}).then (family) ->
            user.updateAttributes family_id: family.id
      ]

  reserveSitter: (accountKey, {sitterId, startTime, endTime, delay}) ->
    startTime = new Date(startTime)
    endTime = new Date(endTime)
    delay ?= DefaultAddSitterDelay
    Q.delay(delay * 1000).then(->
      Sitter.find where: {sitter_id: sitterId}
    ).then((sitter) ->
      logger.info "Sitter(#{sitterId}) = #{sitter.id}"
      return unless sitter
      sitterFirstName = JSON.parse(sitter.data).name.split(/\s/).shift()
      sendMessageTo accountKey,
        messageType: 'sitterConfirmedReservation'
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitterFirstName} has confirmed your request."
        parameters: {sitterId: sitterId, startTime: startTime.toISOString(), endTime: endTime.toISOString()}
    )

  setSitterCount: (accountKey, {count}) ->
    updateSitterListP accountKey, (sitter_ids) ->
      count = Math.max(0, Math.min(7, count))
      return if sitter_ids.length == count
      return _.uniq(sitter_ids.concat([1..7]))[0...count]
