require('dotenv').load()
url = require 'url'
firebase = require '../integrations/firebase'
logger = require('../loggers')('message-bus')

onMessageForAccount = (userAuthId, callback) ->
  userMessageFB = firebase.MessageFB.child(userAuthId)
  logger.info "Simulated user listening on #{url.parse(userMessageFB.toString()).path}"
  userMessageFB.on 'child_added', (snapshot) ->
    key = snapshot.name()
    message = snapshot.val()
    logger.info "Received message #{key}"
    callback message, ->
    userMessageFB.child(key).remove()

onServerRequest = (callback) ->
  logger.info "Polling #{firebase.RequestFB}"
  firebase.RequestFB.on 'child_added', (snapshot) ->
    key = snapshot.name()
    request = snapshot.val()
    callback request, ->
    RequestFB.child(key).remove()

sendMessageToAccount = (userAuthId, message) ->
  MessageFB.child(userAuthId).push message

sendRequestToServer = (request) ->
  firebase.RequestFB.push request

module.exports = {
  onMessageForAccount
  onServerRequest
  sendMessageToAccount
  sendRequestToServer
}
