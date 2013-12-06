url = require 'url'
Q = require 'q'
firebase = require '../lib/firebase'
Winston = require 'winston'
logger = Winston.loggers.add 'client', console:{colorize:true, label:'client'}

API_VERSION = 1

# How many seconds should a simulated sitter wait before responding to an invitation?
DefaultSitterResponseDelay = process.env.DEFAULT_SITTER_CONFIRMATION_DELAY || 20

class Client
  constructor: (@user) ->

  run: ->
    @user.getAccounts().then (accounts) =>
      throw new Error("Can't emulate user ##{@user.id}. No associated account.") unless accounts.length
      @userAuthId = accounts[0].authKey
      userMessageFB = firebase.MessageFB.child(@userAuthId)
      logger.info "Simulated user ##{@user.id} listing on #{url.parse(userMessageFB.toString()).path}"
      userMessageFB.on 'child_added', (snapshot) =>
        key = snapshot.name()
        message = snapshot.val()
        logger.info "Received message #{key}"
        userMessageFB.child(key).remove()
        @processMessage message

  sendRequest: (requestType, parameters) ->
    request =
      requestType : requestType
      apiVersion  : API_VERSION
      # deviceUuid  : Defaults.deviceUuid
      parameters  : parameters
      timestamp   : new Date().toISOString()
      userAuthId  : @userAuthId
    logger.info "Sending request #{requestType}"
    firebase.RequestFB.push request

  processMessage: ({messageType, parameters:{invitationId, simulatedDelay, startTime, endTime}}) ->
    logger.info "Processing #{messageType}"
    simulatedDelay ?= DefaultSitterResponseDelay
    switch messageType
      when 'inviteSitterToFamily', 'reserveSitterForTime'
        logger.info "Waiting #{simulatedDelay}s" if simulatedDelay > 0
        Q.delay(simulatedDelay * 1000)
        .then(=> @sendRequest 'acceptInvitation', {invitationId, startTime, endTime})
        .done()

module.exports = Client
