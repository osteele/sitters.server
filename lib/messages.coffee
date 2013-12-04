# Send messages to client.

#
# Imports
# --
#

require('dotenv').load()
_ = require 'underscore'
Q = require 'q'
_(global).extend require('./models')


#
# Constants
# --
#

# The client and server embed the API version in requests and responses.
API_VERSION = 1


#
# Configure Logging
# --
#

Winston = require 'winston'
logger = Winston.loggers.add 'messages', console:{colorize:true, label:'messages'}


#
# Firebase
# --
#

firebase = require './firebase'
_(global).extend firebase
firebase.authenticateAs {}, {admin:true}

# Send a message to the client, via Firebase and APNS.
#
# `message`:
# - `messageType`  : String -- client keys behavior off of this
# - `messageTitle` : String -- UIAlert title
# - `messageText`  : String -- UIAlert text; also, push notification text
# - `parameters`   : Hash -- client interprets message against this
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

module.exports =
  # The sitter accepted an invitation to join the family's sitter list. Tell the parent (accountKey).
  sitterAcceptedConnection: (accountKey, {sitter}) ->
    sendMessageTo accountKey,
      messageType: 'sitterAcceptedConnection'
      messageTitle: 'Sitter Confirmed'
      messageText: "#{sitter.firstName} has accepted your request. We’ve added her to your Seven Sitters."
      parameters: {sitterId:sitter.id}

  # The sitter accepted a booking. Tell the parent (accountKey).
  sitterConfirmedReservation: (accountKey, {sitter, startTime, endTime}) ->
    sendMessageTo accountKey,
      messageType: 'sitterConfirmedReservation'
      messageTitle: 'Sitter Confirmed'
      messageText: "#{sitter.firstName} has confirmed your request."
      parameters: {sitterId:sitter.id, startTime:startTime.toISOString(), endTime:endTime.toISOString()}

