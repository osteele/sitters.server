# require 'dotenv'
# console.log process.env.FIREBASE_SECRET

# Q = require 'q'
util = require 'util'
Firebase = require 'firebase'

models = require './models'
# findFamily = Q.nbind models.Family.find, models.Family
# findSitter = Q.nbind models.Sitter.find, models.Sitter

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
requestsFB = rootFB.child('request')
messagesFB = rootFB.child('message')
erroredFB = rootFB.child('errored')

requestsFB.on 'child_added', (snapshot) ->
  key = snapshot.name()
  message = snapshot.val()
  console.log "Request #{util.inspect(message)}"
  try
    handleRequestFrom message.accountKey, message.requestType, message.parameters
  catch e
    erroredFB << message
  requestsFB.child(key).remove()

handleRequestFrom = (accountKey, requestType, parameters) ->
  handler = handlers[requestType]
  console.error "Unknown request type #{requestType}" unless handler
  handler?(accountKey, parameters)

sendMessageTo = (accountKey, message) ->
  console.log "Send #{util.inspect(message)} -> #{accountKey}"
  messagesFB.child(accountKey).push message

handlers =
  addSitter: (accountKey, {familyId, sitterId}) ->
    # family = models.Family.find familyId
    # sitter = models.Sitter.find sitterId
    # Q.all([family, sitter]).spread( (family, sitter) ->
    #   console.log 'family', familyId, family
    #   console.log 'sitter', sitterId, sitter #.data.name
    # ).done (->console.log 'fulfilled'), (->console.log 'rejected'), (->console.log 'progress')
    models.Family.find familyId, (error, family) ->
      console.log 'family', familyId, family
      models.Sitter.find sitterId, (error, sitter) ->
        console.log 'sitter', sitterId, sitter.data.name
    return
    process.exit()

    sitterIdsRef = rootFB.child("family/#{familyId}/sitter_ids")

    sitterIdsRef.once 'value', (snapshot) ->
      sitterIds = snapshot.val()
      return if sitterId in sitterIds
      sitterIdsRef.set sitterIds.concat([sitterId])
      sendMessageTo accountKey,
        messageType: 'addedSitter',
        messageTitle: 'Sitter Confirmed',
        messageText:'{{sitter.firstName}} has accepted your request. We’ve added her to your Seven Sitters.',
        parameters: {sitterId}

    # sitterIdsRef.transaction (sitterIds) ->
    #   return if sitterId in sitterIds
    #   return sitterIds.concat([sitterId])
    # , (error, committed, snapshot) ->
    #   messagesFB.child(accountKey).push messageType: 'addedSitter', sitterId: sitterId
