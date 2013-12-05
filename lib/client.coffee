Q = require 'q'
firebase = require '../lib/firebase'
Winston = require 'winston'
logger = Winston.loggers.add 'client', console:{colorize:true, label:'client'}

API_VERSION = 1
DefaultSitterResponseDelay = process.env.DEFAULT_SITTER_CONFIRMATION_DELAY || 20

class Client
  constructor: (@user) ->

  run: ->
    @user.getAccounts().then (accounts) =>
      throw new Error("Can't emulate user ##{@user.id}. No associated account.") unless accounts.length
      @userAuthId = accounts[0].authKey
      userMessageFB = firebase.MessageFB.child(@userAuthId)
      logger.info "Listening on #{userMessageFB}"
      userMessageFB.on 'child_added', (snapshot) =>
        key = snapshot.name()
        message = snapshot.val()
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

  processMessage: ({messageType, parameters:{invitationId, delay}}) ->
    logger.info "Processing #{messageType}"
    delay ?= DefaultSitterResponseDelay
    switch messageType
      when 'inviteSitterToFamily'
        logger.info "Waiting #{delay}s" if delay > 0
        Q.delay(delay * 1000)
        .then(=> @sendRequest 'acceptInvitation', {invitationId})
        .done()

module.exports = Client
