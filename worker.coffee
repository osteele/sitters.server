require('dotenv').load()
_ = require 'underscore'
Q = require 'q'
Q.longStackSupport = true unless process.env.ENVIRONMENT == 'production' and not process.env.DEBUG_SERVER
util = require 'util'
moment = require 'moment'
stripe = require('stripe')(process.env.STRIPE_SECRET_KEY)
_(global).extend require('./lib/models')


#
# Logging
#

Winston = require 'winston'
loggerConsoleOptions = {colorize:true, label:'workers'}
loggerConsoleOptions = {timestamp:true} if process.env.ENVIRONMENT == 'production'
# loggerConsoleOptions.timestamp = -> moment().format('H:MM:ss')
logger = Winston.loggers.add 'workers', console:loggerConsoleOptions


#
# Raven / Sentry
#

raven = require('raven')
RavenClient = new raven.Client(process.env.SENTRY_DSN, stackFunction:Error.prepareStackTrace)
RavenClient.patchGlobal ->
  logger.error 'Exiting'
  process.exit 1
logger.info 'Raven connection to', process.env.SENTRY_DSN

#
# APNS
#

APNS = require('./lib/push')

# `message`:
#   messageType: String -- client keys behavior off of this
#   messageTitle: String -- UIAlert title
#   messageText: String -- UIAlert text; also, push notification text
#   parameters: Hash -- client interprets message against this
sendMessageTo = (accountKey, message) ->
  logger.info "Send -> #{accountKey}:", message
  firebaseMessageId = MessageFB.child(accountKey).push message
  payload = _.extend {}, message
  delete payload.messageText
  # logger.info "firebaseMessageId = #{firebaseMessageId}"
  accountKeyDeviceTokensP(accountKey).then (tokens) ->
    for token in tokens
      APNS.pushMessageTo token, alert: message.messageText, payload: payload

APNS.connection.on 'transmissionError', (errCode, notification, device) ->
  return unless errCode == 8 # invalid token
  token = device.token.toString('hex')
  logger.info "Removing device token=#{token}"
  sequelize.query('DELETE FROM devices WHERE token=:token', null, {raw:true}, {token}).then(->
    logger.info "Deleted token=#{token}"
  ).done()

# TODO race condition with database initialization
APNS.feedback.on 'feedback', (devices) ->
  devices.forEach (item) ->
    token = item.device.token.toString('hex')
    sequelize.query('DELETE FROM devices WHERE token=:token AND updated_at < :time', null, {raw:true}, {token, time: item.time}).then(->
      logger.info "Deleted token=#{token}"
    ).done()


#
# Firebase
#

Firebase = require('./lib/firebase')
_(global).extend Firebase
Firebase.authenticateAs {}, {admin:true}

# protect from partial application
updateFirebaseFromDatabaseP = do ->
  fn = require('./lib/push_to_firebase').updateSomeP
  -> fn()


#
# Client Messages
#

SendClientMessage =
  sitterAcceptedConnection: (accountKey, {sitter}) ->
      sendMessageTo accountKey,
        messageType: 'sitterAcceptedConnection'
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitter.firstName} has accepted your request. We’ve added her to your Seven Sitters."
        parameters: {sitterId}

  sitterConfirmedReservation: (accountKey, {sitter, startTime, endTime}) ->
      sendMessageTo accountKey,
        messageType: 'sitterConfirmedReservation'
        messageTitle: 'Sitter Confirmed'
        messageText: "#{sitter.firstName} has confirmed your request."
        parameters: {sitterId, startTime:startTime.toISOString(), endTime:endTime.toISOString()}


#
# Request Handling
#

DefaultSitterConfirmationDelay = 20
MaxSitterCount = 7

logger.info "Polling #{RequestFB}"

RequestFB.on 'child_added', (snapshot) ->
  key = snapshot.name()
  request = snapshot.val()
  try
    processRequest request
  finally
    RequestFB.child(key).remove()

processRequest = (request) ->
  RavenClient.captureMessage requestType
  {accountKey, requestType, parameters} = request
  parameters ||= {}
  logger.info "Processing request #{requestType} from #{accountKey} with #{JSON.stringify(parameters).replace(/"(\w+)":/g, '$1:')}"
  handler = RequestHandlers[requestType]
  unless handler
    logger.error "Unknown request type #{requestType}"
    return
  promise = handler(accountKey, parameters)
  promise = promise.then(updateFirebaseFromDatabaseP)
  promise.done()

RequestHandlers =
  addSitter: (accountKey, {sitterId, delay}) ->
    delay ?= DefaultSitterConfirmationDelay
    sitter = null
    Q.delay(delay * 1000
    ).then(->
      Sitter.find(sitterId)
    ).then((sitter_) ->
      sitter = sitter_
      logger.error "Unknown sitter ##{sitterId}"
      return unless sitter
      updateSitterListP accountKey, (sitter_ids) ->
        logger.info "Adding sitter", sitterId, "to", sitter_ids
        return if sitterId in sitter_ids
        return sitter_ids.concat([sitterId])
    ).then((modified) ->
      logger.info "Sitter was already added" unless modified
      return unless modified
      SendClientMessage.sitterAcceptedConnection accountKey, {sitter}
    )

  registerDeviceToken: (accountKey, {token}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    accountP = Account.find where: {provider_name, provider_user_id}
    deviceP = Device.find where: {token}
    Q.all([accountP, deviceP]).spread (account, device) ->
      logger.info "Register device token=#{token} for device=#{device?.id} account=#{account?.id}"
      return if device and account.user_id == device.user_id
      if device
        logger.info "Update device ##{device.id}"
        device.updateAttributes user_id: account.user_id
      else
        logger.info "Register device"
        Device.create {token, user_id: account.user_id}

  registerPaymentToken: (accountKey, {token, cardInfo}) ->
    user = null
    User.findByAccountKey(accountKey).then((user_) ->
      user = user_
      logger.info "Found user ##{user.id}"
      return unless user
      PaymentCustomer.findOrCreate user_id:user.id
    ).then (customerRow) ->
      email = user.email
      metadata = {user_id:user.id}
      if customerRow?.stripe_customer_id
        logger.info "Found customer #{customerRow.stripe_customer_id}"
        stripe.customers.update(customerRow.stripe_customer_id, {card:token, email, metadata}).then ->
          customerRow.updateAttributes card_info:cardInfo
      else
        stripe.customers.create({card:token, email, metadata}).then (stripeCustomer) ->
          logger.info "New customer #{stripeCustomer.id}"
          attrs = {stripe_customer_id:stripeCustomer.id, card_info:cardInfo}
          PaymentCustomer.findOrCreate({user_id:user.id}, attrs).then (customerRow) ->
            customerRow.updateAttributes attrs

  registerUser: (accountKey, {displayName, email}) ->
    [provider_name, provider_user_id] = accountKey.split('/', 2)
    accountP = Account.findOrCreate {provider_name, provider_user_id}
    userP = User.findOrCreate {email}, {displayName}
    Q.all([accountP, userP]).spread (account, user) ->
      logger.info "Account key=#{accountKey}" if account
      logger.info "Update account #{account?.id} user_id=#{user?.id}"
      # return if user.hasAccount(account)
      Q.all [
        account.updateAttributes user_id:user.id
        user.updateAttributes {displayName} #unless user.displayName == displayName,
        Family.find(user.family_id).then (family) ->
          return if family
          Family.create({sitter_ids: '{}'}).then (family) ->
            user.updateAttributes family_id:family.id
      ]

  removePaymentCard: (accountKey, {}) ->
    user = null
    User.findByAccountKey(accountKey).then((user_) ->
      user = user_
      PaymentCustomer.find where: {user_id:user.id}
    ).then (customerRow) ->
      customerId = customerRow?.stripe_customer_id
      return unless customerId
      removeCardInfo = -> customerRow.updateAttributes card_info:{}
      stripe.customers.retrieve(customerId).then (customer) ->
        cardId = customer.cards.data[0]?.id
        if cardId
          stripe.customers.deleteCard(customerId, cardId).then removeCardInfo
        else
          removeCardInfo()

  reserveSitter: (accountKey, {sitterId, startTime, endTime, delay}) ->
    delay ?= DefaultSitterConfirmationDelay
    startTime = new Date(startTime)
    endTime = new Date(endTime)
    Q.delay(delay * 1000).then(->
      Sitter.find(sitterId)
    ).then((sitter) ->
      logger.error "Unknown sitter ##{sitterId}"
      return unless sitter
      SendClientMessage.sitterConfirmedReservation accountKey, {sitter, startTime, endTime}
    )

  setSitterCount: (accountKey, {count}) ->
    updateSitterListP accountKey, (sitter_ids) ->
      count = Math.max(0, Math.min(MaxSitterCount, count))
      return if sitter_ids.length == count
      return _.uniq(sitter_ids.concat([1..7]))[0...count]

  simulateServerError: ->
    return unless process.env.DEBUG_SERVER
    Q.delay(1).then ->
