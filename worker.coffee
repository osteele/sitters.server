# require 'dotenv'
# console.log process.env.FIREBASE_SECRET
util = require 'util'
Firebase = require 'firebase'

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
requestsFB = rootFB.child('request')
messagesFB = rootFB.child('message')
erroredFB = rootFB.child('errored')

requestsFB.on 'child_added', (snapshot) ->
  key = snapshot.name()
  message = snapshot.val()
  console.log "Request #{util.inspect(message)}"
  try
    handleRequestFrom message.userId, message.requestType, message.parameters
  catch e
    console.error e
    erroredFB << message
  requestsFB.child(key).remove()

handleRequestFrom = (userId, requestType, parameters) ->
  handler = handlers[requestType]
  console.log "Unknown request type #{requestType}" unless handler
  handler?(userId, parameters)

sendMessageTo = (userId, message) ->
  console.log "Send #{util.inspect(message)} -> #{userId}"
  messagesFB.child(userId).push message

handlers =
  addSitter: (userId, {familyId, sitterId}) ->
    console.log "family/#{familyId}/sitter_ids"
    sitterIdsRef = rootFB.child("family/#{familyId}/sitter_ids")

    sitterIdsRef.once 'value', (snapshot) ->
      sitterIds = snapshot.val()
      return if sitterId in sitterIds
      sitterIdsRef.set sitterIds.concat([sitterId])
      sendMessageTo userId,
        messageType: 'addedSitter',
        messageTitle: 'Sitter Confirmed',
        messageText:'{{sitter.firstName}} has accepted your request. We’ve added her to your Seven Sitters.',
        parameters: {sitterId}

    # sitterIdsRef.transaction (sitterIds) ->
    #   return if sitterId in sitterIds
    #   return sitterIds.concat([sitterId])
    # , (error, committed, snapshot) ->
    #   messagesFB.child(userId).push messageType: 'addedSitter', sitterId: sitterId
