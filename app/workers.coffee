#!/usr/bin/env coffee

# This file defines the worker processes that process client requests.
#
# It can be run standalone. The web server also includes it.

# Set the process's title so it's easier to find in `ps`, # `top`, Activity Monitor, and so on.
process.title = 'sitters.workers'


#
# Imports
# --

require('dotenv').load()
_ = require 'underscore'
Q = require 'q'
Q.longStackSupport = true unless process.env.NODE_ENV == 'production' and not process.env.DEBUG_SERVER
util = require 'util'
moment = require 'moment'
kue = require './integrations/kue'
jobs = kue.createQueue()
_(global).extend require('./lib/models')
logger = require('./loggers')('workers')


#
# Rollbar
# --

if process.env.ROLLBAR_ACCESS_TOKEN
  rollbar = require 'rollbar'
  rollbar.init process.env.ROLLBAR_ACCESS_TOKEN
else
  rollbar =
    reportMessage: ->
    handleError: (err) -> throw err

process.on 'uncaughtException', (err) ->
  console.error err.stack
  logger.error 'Fatal uncaught exception', err.message, ->
    rollbar.handleError err, ->
      rollbar.shutdown ->
        process.exit 1


#
# APNS
# --

APNS = require('./integrations/apns')

# Remove devices with invalid tokens.
APNS.connection.on 'transmissionError', (errCode, notification, device) ->
  return unless errCode == 8 # invalid token
  token = device.token.toString('hex')
  logger.info "Removing device token=#{token}"
  sequelize.query('DELETE FROM devices WHERE token=:token', null, {raw:true}, {token})
    .then(-> logger.info "Deleted token=#{token}")
    .done()

# Remove devices with invalid tokens.
#
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

firebase = require './integrations/firebase'
firebase.authenticateAs {}, {admin:true}

updateFirebaseFromDatabase = require('./lib/push_to_firebase').updateAllP

# Work through backlog from previous server failure.
updateFirebaseFromDatabase().then (count) ->
  logger.info "Updated backlog of #{count} firebase records" if count > 0


#
# Handle requests
# --

# The client pushes requests to Firebase, which handles auth.
# Move them from Firebase to the job queue.
messageBus = require './lib/message_bus'
messageBus.onRequest (request) ->
  title = "#{request.requestType} from #{request.userAuthId}"
  jobs.create('request', {request, title}).save()

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
  # The request will generally update some database entities. Update Firebase from these.
  # This will also work through some of a backlog in case of a previous server failure.
  promise = promise.then -> updateFirebaseFromDatabase()
  return promise

RequestHandlers = require './request-handlers'


#
# Create virtual clients for simulated sitters and run them in-process
# --

Client = require './lib/client'

simulateSittersP =
  SitterProfile.findAll(where:{is_simulated:true})
  .then (sitterProfiles) ->
    Q.all sitterProfiles.map (sitterProfile) ->
      sitterProfile.getUser().then (user) ->
        new Client(user).run()

simulateSittersP.done()


# Exports
# --
exports.jobs = jobs
