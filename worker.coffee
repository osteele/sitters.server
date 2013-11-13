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

DefaultSitterConfirmationDelay = 20

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
environmentFB = rootFB
environmentFB = environmentFB.child(process.env.ENVIRONMENT) if process.env.ENVIRONMENT
requestsFB = environmentFB.child('request')
messagesFB = environmentFB.child('message')
accountFB = environmentFB.child('account')
familyFB = environmentFB.child('family')

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

MessageTypes =
  sitterConfirmedReservation: 'sitterConfirmedReservation'
  sitterAcceptedConnection: 'sitterAcceptedConnection'

# `message`:
#   messageType: String -- client keys behavior off of this
#   messageTitle: String -- UIAlert title
#   messageText: String -- UIAlert text; also, push notification text
#   parameters: Hash -- client interprets message against this
sendMessageTo = (accountKey, message) ->
  logger.info "Send -> #{accountKey}:", message
  firebaseMessageId = messagesFB.child(accountKey).push message
  # logger.info "firebaseMessageId = #{firebaseMessageId}"
  accountKeyDeviceTokensP(accountKey).then (tokens) ->
    for token in tokens
      logger.info "  Push #{message.messageType} -> #{token}"
      pushMessageTo token, alert: message.messageText, payload: message

updateSitterListP = (accountKey, fn) ->
  accountKeyUserFamilyP(accountKey).then (family) ->
    return unless family
    sitter_ids = fn(family.sitter_ids)
    return Q(false) unless sitter_ids
    family.updateAttributes({sitter_ids}).then ->
      familyFB.child(String(family.id)).child('sitter_ids').set sitter_ids
      Q(true)

handlers =
  addSitter: (accountKey, {sitterId, delay}) ->
    delay ?= DefaultSitterConfirmationDelay
    Q.delay(delay * 1000).then(-> updateSitterListP(accountKey, (sitter_ids) ->
      logger.info "Adding sitter", sitterId, "to", sitter_ids
      return if sitterId in sitter_ids
      return sitter_ids.concat([sitterId])
    )).then((modified) ->
      logger.info "Sitter was already added" unless modified
      return unless modified
      Sitter.find(sitterId)
    ).then((sitter) ->
      return unless sitter
      sendMessageTo accountKey,
        messageType: MessageTypes.sitterAcceptedConnection
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitter.firstName} has accepted your request. We’ve added her to your Seven Sitters."
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
            user.updateAttributes(family_id: family.id).then ->
              accountFB.child(provider_name).child(provider_user_id).child('family_id').set family.id
      ]

  reserveSitter: (accountKey, {sitterId, startTime, endTime, delay}) ->
    delay ?= DefaultSitterConfirmationDelay
    startTime = new Date(startTime)
    endTime = new Date(endTime)
    Q.delay(delay * 1000).then(->
      Sitter.find(sitterId)
    ).then((sitter) ->
      logger.info "Sitter(#{sitterId}) = #{sitter.id}"
      return unless sitter
      sendMessageTo accountKey,
        messageType: MessageTypes.sitterConfirmedReservation
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitter.firstName} has confirmed your request."
        parameters: {sitterId: sitterId, startTime: startTime.toISOString(), endTime: endTime.toISOString()}
    )

  setSitterCount: (accountKey, {count}) ->
    updateSitterListP accountKey, (sitter_ids) ->
      count = Math.max(0, Math.min(7, count))
      return if sitter_ids.length == count
      return _.uniq(sitter_ids.concat([1..7]))[0...count]
