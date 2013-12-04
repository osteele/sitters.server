# This file defines the worker processes that process client requests.
#
# It can be run standalone, and is also currently run as part of the web server.

# Set the process's title so it's easier to find in `ps`, # `top`, Activity Monitor, and so on.
process.title = 'sitters.workers'


#
# Imports
# --
#

require('dotenv').load()
_ = require 'underscore'
Q = require 'q'
Q.longStackSupport = true unless process.env.NODE_ENV == 'production' and not process.env.DEBUG_SERVER
util = require 'util'
moment = require 'moment'
kue = require './lib/kue'
jobs = kue.createQueue()
stripe = require('stripe')(process.env.STRIPE_SECRET_KEY)
_(global).extend require('./lib/models')


#
# Globals and Constants
# --
#

# The client and server embed the API version in requests and responses.
API_VERSION = 1
DefaultSitterConfirmationDelay = process.env.DEFAULT_SITTER_CONFIRMATION_DELAY || 20
MaxSitterCount = 7



#
# Configure Logging
# --
#

Winston = require 'winston'
logger = Winston.loggers.add 'workers', console:{colorize:true, label:'workers'}


#
# Rollbar integration
# --
#

if process.env.ROLLBAR_ACCESS_TOKEN
  rollbar = require 'rollbar'
  rollbar.init process.env.ROLLBAR_ACCESS_TOKEN
else
  rollbar =
    reportMessage: ->

process.on 'uncaughtException', (err) ->
  console.error err.stack
  logger.error 'Fatal uncaught exception', err.message, ->
    rollbar.handleError err, ->
      rollbar.shutdown ->
        process.exit 1


#
# APNS
# --
#

APNS = require('./lib/push')

APNS.connection.on 'transmissionError', (errCode, notification, device) ->
  return unless errCode == 8 # invalid token
  token = device.token.toString('hex')
  logger.info "Removing device token=#{token}"
  sequelize.query('DELETE FROM devices WHERE token=:token', null, {raw:true}, {token})
    .then(-> logger.info "Deleted token=#{token}")
    .done()

# TODO race condition with database initialization
APNS.feedback.on 'feedback', (devices) ->
  devices.forEach (item) ->
    token = item.device.token.toString('hex')
    sequelize.execute('DELETE FROM devices WHERE token=:token AND updated_at<:time', {token, time:item.time})
      .then -> logger.info "Deleted token=#{token}"
      .done()


#
# Firebase
# --
#

firebase = require './lib/firebase'
_(global).extend firebase
firebase.authenticateAs {}, {admin:true}

updateSomeP = require('./lib/push_to_firebase').updateSomeP


#
# Client Messages
# --
#

# `message`:
#   messageType  : String -- client keys behavior off of this
#   messageTitle : String -- UIAlert title
#   messageText  : String -- UIAlert text; also, push notification text
#   parameters   : Hash -- client interprets message against this
sendMessageTo = (accountKey, message) ->
  logger.info "Send -> #{accountKey}:", message

  payload = _.extend {}, message,
    timestamp: new Date().toISOString()
    apiVersion: API_VERSION
  messageId = MessageFB.child(accountKey).push(payload).name()

  payload = _.extend {}, message
  delete payload.messageText
  accountKeyDeviceTokensP(accountKey).then (tokens) ->
    for token in tokens
      APNS.pushMessageTo token, alert:message.messageText, payload:payload

SendClientMessage =
  sitterAcceptedConnection: (accountKey, {sitter}) ->
    sendMessageTo accountKey,
      messageType: 'sitterAcceptedConnection'
      messageTitle: 'Sitter Confirmed'
      messageText: "#{sitter.firstName} has accepted your request. We’ve added her to your Seven Sitters."
      parameters: {sitterId:sitter.id}

  sitterConfirmedReservation: (accountKey, {sitter, startTime, endTime}) ->
    sendMessageTo accountKey,
      messageType: 'sitterConfirmedReservation'
      messageTitle: 'Sitter Confirmed'
      messageText: "#{sitter.firstName} has confirmed your request."
      parameters: {sitterId:sitter.id, startTime:startTime.toISOString(), endTime:endTime.toISOString()}


#
# Request Handling
# --
#

logger.info "Polling #{RequestFB}"

# The client pushes requests to Firebase, which handles auth.
# Move them from Firebase to the job queue.
RequestFB.on 'child_added', (snapshot) ->
  key = snapshot.name()
  request = snapshot.val()
  title = "#{request.requestType} from #{request.userAuthId}"
  jobs.create('request', {request, title}).save()
  RequestFB.child(key).remove()

jobs.process 'request', (job, done) ->
  processRequest(job.data.request)
    .then(
      -> done()
      (err) ->
        logger.error err
        rollbar.handleError err
        done err
    ).done()

processRequest = (request) ->
  {userAuthId, requestType, parameters} = request
  rollbar.reportMessage "Process #{requestType}", 'info'
  accountKey = userAuthId.replace('/', '-')
  parameters ||= {}
  do ->
    parametersString = JSON.stringify(parameters).replace(/"(\w+)":/g, '$1:')
    logger.info "Processing request #{requestType} from #{accountKey} with #{parametersString}"
  handler = RequestHandlers[requestType]
  unless handler
    logger.error "Unknown request type #{requestType}"
    return
  promise = User.findByAccountKey(accountKey)
  promise = promise.then (user) -> handler {accountKey, user}, parameters
  promise = promise.then -> updateSomeP()
  return promise

RequestHandlers =
  addSitter: ({accountKey, user}, {sitterId, delay}) ->
    delay ?= DefaultSitterConfirmationDelay
    sitter = null
    logger.info "Waiting #{delay}s" if delay > 0
    Q.delay(delay * 1000)
    .then(-> Sitter.find(sitterId))
    .then((sitter_) ->
      sitter = sitter_
      logger.error "Unknown sitter ##{sitterId}" unless sitter
      return unless sitter
      updateUserSitterListP user, (sitter_ids) ->
        logger.info "Adding sitter", sitterId, "to", sitter_ids
        return if sitterId in sitter_ids
        return sitter_ids.concat([sitterId])
    ).then((modified) ->
      logger.info "Sitter was already added" unless modified
      return unless modified
      SendClientMessage.sitterAcceptedConnection accountKey, {sitter}
    )

  registerDeviceToken: ({accountKey}, {token}) ->
    [provider_name, provider_user_id] = accountKey.split('-', 2)
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

  registerPaymentToken: ({user}, {token, cardInfo}) ->
    PaymentCustomer.findOrCreate(user_id:user.id).then (customerRow) ->
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

  registerUser: ({accountKey}, {displayName, email}) ->
    [provider_name, provider_user_id] = accountKey.split('-', 2)
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

  removePaymentCard: ({user}, {}) ->
    PaymentCustomer.find(where: {user_id:user.id}).then (customerRow) ->
      stripeCustomerId = customerRow?.stripe_customer_id
      return unless stripeCustomerId
      removeCardInfo = -> customerRow.updateAttributes card_info:{}
      stripe.customers.retrieve(stripeCustomerId).then (customer) ->
        cardId = customer.cards.data[0]?.id
        if cardId
          stripe.customers.deleteCard(stripeCustomerId, cardId).then removeCardInfo
        else
          removeCardInfo()

  reserveSitter: ({accountKey}, {sitterId, startTime, endTime, delay}) ->
    delay ?= DefaultSitterConfirmationDelay
    startTime = new Date(startTime)
    endTime = new Date(endTime)
    logger.info "Waiting #{delay}s" if delay > 0
    Q.delay(delay * 1000).then(->
      Sitter.find(sitterId)
    ).then((sitter) ->
      logger.error "Unknown sitter ##{sitterId}" unless sitter
      return unless sitter
      SendClientMessage.sitterConfirmedReservation accountKey, {sitter, startTime, endTime}
    )

  setSitterCount: ({user}, {count}) ->
    updateUserSitterListP user, (sitter_ids) ->
      count = Math.max(0, Math.min(MaxSitterCount, count))
      return if sitter_ids.length == count
      return _.uniq(sitter_ids.concat([1..MaxSitterCount]))[0...count]

  simulateServerError: ->
    if process.env.NODE_ENV == 'production' and not process.env.DEBUG_SERVER
      logger.info "Ignoring simulated server error"
      return
    Q.delay(1).then ->
      throw new Error("Simulated server error")
