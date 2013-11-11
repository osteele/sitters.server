util = require 'util'

_ = require 'underscore'
Q = require 'q'
moment = require 'moment'
winston = require 'winston'
Firebase = require 'firebase'

models = require './lib/models'
_(global).extend require('./lib/modelsP')
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
  catch err
    logger.error err
  finally
    requestsFB.child(key).remove()

handleRequestFrom = (accountKey, requestType, parameters) ->
  handler = handlers[requestType]
  logger.error "Unknown request type #{requestType}" unless handler
  promise = handler(accountKey, parameters)
  # delay = parameters.delay
  # logger.info 'delay', delay
  # if delay? or requestType in ['addSitter', 'reserveSitter']
  #   delay ?= DefaultAddSitterDelay
  #   logger.info 'delay', delay
  #   promise = Q.delay(delay).then(promise)
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
  queryP(text: SelectDeviceTokenFromAccountKeySQL, values: [provider_name, provider_user_id]).then (rows) ->
    rows.forEach ({token}) ->
      logger.info "  Push #{message.messageType} -> #{token}"
      pushMessageTo token, alert: message.messageText, payload: message

SelectDeviceTokenFromAccountKeySQL = """
SELECT token
FROM devices
JOIN users ON users.id=devices.user_id
JOIN accounts ON accounts.user_id=users.id
WHERE provider_name=$1 and provider_user_id=$2;"""

SelectAccountUserFamilySQL = """
SELECT families.id AS family_id, sitter_ids
FROM families
JOIN users ON families.id=family_id
JOIN accounts ON users.id=user_id
WHERE provider_name=$1 and provider_user_id=$2;"""

UpdateFamilySittersSQL = "UPDATE families SET sitter_ids=$2 WHERE id=$1;"

updateSitterListP = (accountKey, fn) ->
  [provider_name, provider_user_id] = accountKey.split('/', 2)
  queryP(text: SelectAccountUserFamilySQL, values: [provider_name, provider_user_id]).then (rows) ->
    {family_id, sitter_ids} = rows[0]
    sitter_ids = JSON.parse(sitter_ids)
    sitter_ids = fn(sitter_ids)
    return Q(false) unless sitter_ids
    logger.info "Update sitter_ids <- #{sitter_ids}"
    queryP(text: UpdateFamilySittersSQL, values: [family_id, JSON.stringify(sitter_ids)]).then ->
      logger.info "Updated sitter_ids <- #{sitter_ids}"
      familyFB.child(String(family_id)).child('sitter_ids').set sitter_ids
      Q(true)

handlers =
  addSitter: (accountKey, {sitterId}) ->
    updateSitterListP(accountKey, (sitter_ids) ->
      logger.info "Add sitter #{sitterId} to #{sitter_ids}"
      return if sitterId in sitter_ids
      return sitter_ids.concat([sitterId])
    ).then((modified) ->
      logger.info "Didn't modify sitter id list"
      return unless modified
      logger.info "Added sitter id=#{sitterId}"
      findSitterP(sitterId)
    ).then((sitter) ->
      # logger.info "Couldn't find sitter id=#{sitterId}" unless sitter
      return unless sitter
      logger.info "Sending message add sitter #{sitter.id}"
      sitterFirstName = sitter.data.name.split(/\s/).shift()
      sendMessageTo accountKey,
        messageType: 'sitterAcceptedConnection'
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitterFirstName} has accepted your request. We’ve added her to your Seven Sitters."
        parameters: {sitterId: sitterId}
    )

  registerDeviceToken: (accountKey, {token}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    accountP = findOneAccountP where: {provider_name, provider_user_id}
    deviceP = findOneDeviceP where: {token}
    Q.all([accountP, deviceP]).spread((account, device) ->
      logger.info "Register #{token} for device=#{device} account=#{account}"
      return unless account
      return if device and account.user_id == device.user_id
      if device
        logger.info "Update device #{device}"
        updateAttributesP device, user_id: account.user_id
      else
        logger.info "Create device"
        createDeviceP {token, user_id: account.user_id}
    )

  registerUser: (accountKey, {displayName, email}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    findOneAccountP(where: {provider_name, provider_user_id}).then((account) ->
      logger.info "Found account key=#{accountKey}" if account
      return if account
      logger.info "Creating account key=#{accountKey}" if account
      findOneUserP({email}).then((user) ->
        if user
          logger.info "Found user email=#{email}"
          updateAttributes user, {displayName}
        else
          logger.info "Creating user email=#{email}"
          createUserP {displayName, email}
      ).then((user) ->
        accountP = createAccountP {provider_name, provider_user_id, user_id: user.id}
        familyP = createFamilyP {sitter_ids: []}
        Q.all([accountP, familyP]).spread (account, family) ->
          updateAttributes(user, family_id: family.id).then ->
            Q(family)
      )
    ).then((family) ->
      return unless family
      Q.ninvoke(familyFB.child(String(family.id)), 'set', {sitter_ids: family.sitter_ids}).then ->
        Q.ninvoke accountFB.child(accountKey).child('family_id'), 'set', family.id
    )

  reserveSitter: (accountKey, {sitterId, startTime, endTime}) ->
    startTime = new Date(startTime)
    endTime = new Date(endTime)
    logger.info "Finding sitter #{sitterId}"
    findOneSitterP(where: {sitter_id: sitterId}).then((sitter) ->
      logger.info "findOneSitterP(#{sitterId}) = #{sitter}"
      return unless sitter
      sitterFirstName = sitter.data.name.split(/\s/).shift()
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
