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
# Constants
# --
#

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
# Request Handling
# --
#

SendClientMessage = require './lib/messages'

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
  # The parent sends this to invite a sitter who is already in the system to join the parent's family sitters. `delay`
  # is used for development and debugging; it sets the amount of time that one of the simulated sitters will wait before
  # responding.
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

  # The client sends this when the user signs in, and on each launch if the user is already signed in. The server
  # creates or updates a Device record and associates it with the user, for use with mobile notifications.
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

  # The client sends this when the user enters a payment card. THe server ensures the existence of a Stripe customer for
  # this user, and creates or replaces the payment card. The server also stores the card display information in the
  # database, for display in the client UI.
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

  # The client sends this when a user signs in, and on each launch if the user is already signed in. The server ensures
  # that a User record exists, associates it with the account that the user authenticated with, and ensures that a
  # Family for this user exists.
  registerUser: ({accountKey}, {displayName, email}) ->
    [provider_name, provider_user_id] = accountKey.split('-', 2)
    accountP = Account.findOrCreate {provider_name, provider_user_id}
    userP = User.findOrCreate {email}, {displayName}
    Q.all([accountP, userP]).spread (account, user) ->
      logger.info "Account key=#{accountKey}" if account
      logger.info "Update account #{account?.id} user_id=#{user?.id}"
      Q.all [
        account.updateAttributes user_id:user.id
        user.updateAttributes {displayName} #unless user.displayName == displayName,
        Family.find(user.family_id).then (family) ->
          return if family
          Family.create({sitter_ids: '{}'}).then (family) ->
            user.updateAttributes family_id:family.id
      ]

  # The client sends this when the user removes their payment card.
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

  # The client sends this when the user requests a specific sitter for a specific time.
  # `delay` is used for development and debugging; it sets the amount of time that one
  # of the simulated sitters will wait before responding.
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

  # This message is used for testing. It changes the number of sitters associated with the user's family, filling them
  # in as needed from the simulated sitters.
  setSitterCount: ({user}, {count}) ->
    updateUserSitterListP user, (sitter_ids) ->
      count = Math.max(0, Math.min(MaxSitterCount, count))
      return if sitter_ids.length == count
      return _.uniq(sitter_ids.concat([1..MaxSitterCount]))[0...count]

  # This message is used for testing, to test server error handling and reporting. It throws an error. If running in the
  # production environment, it only throws an error if the `DEBUG_SERVER` environment variable is set.
  simulateServerError: ->
    if process.env.NODE_ENV == 'production' and not process.env.DEBUG_SERVER
      logger.info "Ignoring simulated server error"
      return
    Q.delay(1).then ->
      throw new Error("Simulated server error")
