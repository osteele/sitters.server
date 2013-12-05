# Send messages to client.

#
# Imports
# --

require('dotenv').load()
_ = require 'underscore'
Q = require 'q'
APNS = require('./apns')
_(global).extend require('./models')


#
# Constants
# --

# The client and server embed the API version in requests and responses.
API_VERSION = 1


#
# Configure Logging
# --

Winston = require 'winston'
logger = Winston.loggers.add 'messages', console:{colorize:true, label:'messages'}


#
# Firebase
# --

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
sendMessageTo = (user, message) ->
  logger.info "Send -> user ##{user.id}:", message

  firebaseMessage = _.extend {}, message,
    apiVersion : API_VERSION
    timestamp  : new Date().toISOString()
  user.getAccounts().then (accounts) ->
    accounts.forEach (account) ->
      fb = MessageFB.child(account.firebaseKey).push(firebaseMessage)
      logger.info "message -> #{account.firebaseKey}/#{fb.name()}"

  payload = _.extend {}, message
  delete payload.messageText
  user.getDevices().then (devices) ->
    devices.forEach ({token}) ->
      if token
        APNS.pushMessageTo token, alert:message.messageText, payload:payload

module.exports =
  inviteSitterToFamily: (sitter, {invitation, parent}) ->
    sendMessageTo sitter,
      messageType: 'inviteSitterToFamily'
      messageTitle: 'Sitter Request'
      messageText: "#{parent.displayName} has requested to add you to her seven sitters. Please review."
      parameters: {invitationId:invitation.id}

  # The sitter accepted an invitation to join the family's sitter list. Tell the parent (user).
  sitterAcceptedConnection: (user, {sitter}) ->
    sendMessageTo user,
      messageType: 'sitterAcceptedConnection'
      messageTitle: 'Sitter Confirmed'
      messageText: "#{sitter.firstName} has accepted your request. We’ve added her to your Seven Sitters."
      parameters: {sitterId:sitter.id}

  # The sitter accepted a booking. Tell the parent (user).
  sitterConfirmedReservation: (user, {sitter, startTime, endTime}) ->
    sendMessageTo user,
      messageType: 'sitterConfirmedReservation'
      messageTitle: 'Sitter Confirmed'
      messageText: "#{sitter.firstName} has confirmed your request."
      parameters: {sitterId:sitter.id, startTime:startTime.toISOString(), endTime:endTime.toISOString()}


