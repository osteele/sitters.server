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
_(global).extend require('./lib/models')


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

APNS = require('./lib/apns')

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

updateFirebaseFromDatabase = require('./lib/push_to_firebase').updateAllP

# Work through backlog from previous server failure.
updateFirebaseFromDatabase().then (count) ->
  logger.info "Updated backlog of #{count} firebase records" if count > 0


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
  # The request will generally update some database entities. Update Firebase from these.
  # This will also work through some of a backlog in case of a previous server failure.
  promise = promise.then -> updateFirebaseFromDatabase()
  return promise

RequestHandlers = require './lib/request-handlers'
