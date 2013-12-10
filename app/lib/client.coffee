require('dotenv').load()
Q = require 'q'
messageBus = require './message_bus'
logger = require('../loggers')('client')

API_VERSION = 1

# How many seconds should a simulated sitter wait before responding to an invitation?
DefaultSitterResponseDelay = process.env.DEFAULT_SITTER_CONFIRMATION_DELAY || 20

class Client
  constructor: (@user) ->
    d = Q.defer()
    @messageReceivedP = d.promise
    @_messageReceivedNotify = (msg) -> d.notify msg
    @userAuthP =
      @user.getAccounts().then (accounts) =>
        throw new Error("Can't emulate user ##{@user.id}. No associated account.") unless accounts.length
        accounts[0].authKey

  run: ->
    @userAuthP.then((userAuthId) =>
      messageBus.onMessageForAccount userAuthId, (message) =>
        @_messageReceivedNotify message
        @processMessage message
    ).done()
    return this

  sendRequestP: (requestType, parameters) ->
    @userAuthP.then (userAuthId) =>
      request =
        requestType : requestType
        apiVersion  : API_VERSION
        # deviceUuid  : Defaults.deviceUuid
        parameters  : parameters
        timestamp   : new Date().toISOString()
        userAuthId  : userAuthId
      logger.info "Sending request #{requestType}"
      messageBus.sendRequestToServer request

  sendRequest: (requestType, parameters) ->
    @sendRequestP(requestType, parameters).done()

  processMessage: ({messageType, parameters}) ->
    logger.info "Processing #{messageType}"
    {simulatedDelay} = parameters
    simulatedDelay ?= DefaultSitterResponseDelay
    switch messageType
      when 'inviteSitterToFamily', 'reserveSitterForTime'
        logger.info "Waiting #{simulatedDelay}s" if simulatedDelay > 0
        Q.delay(simulatedDelay * 1000)
        .then(=> @sendRequest 'acceptInvitation', parameters)
        .done()

module.exports = Client
