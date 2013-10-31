# require 'dotenv'
# console.log process.env.FIREBASE_SECRET

Firebase = require('firebase')
rootRef = new Firebase('https://sevensitters.firebaseIO.com/')
requestRef = rootRef.child('request')
messageRef = rootRef.child('messages')

requestRef.on 'child_added', (snapshot) ->
  key = snapshot.name()
  data = snapshot.val()
  try
    handleRequest data.requestType, data
  catch e
    console.log e
  requestRef.child(snapshot.name()).remove()

handleRequest = (requestType, data) ->
  handler = handlers[requestType]
  console.log "Unknown request type #{requestType}" unless handler
  handler?(data)

handlers =
  addSitter: (data) ->
    userId = data.userId
    familyId = data.familyId
    sitterId = data.sitterId
    sitterIdsRef = rootRef.child("family/#{familyId}/sitter_ids")

    sitterIdsRef.once 'value', (snapshot) ->
      sitterIds = snapshot.val()
      return if sitterId in sitterIds
      sitterIdsRef.set sitterIds.concat([sitterId])
      messageRef.child(userId).push messageType: 'addedSitter', sitterId: sitterId

    # sitterIdsRef.transaction (sitterIds) ->
    #   return if sitterId in sitterIds
    #   return sitterIds.concat([sitterId])
    # , (error, committed, snapshot) ->
    #   messageRef.child(userId).push messageType: 'addedSitter', sitterId: sitterId
