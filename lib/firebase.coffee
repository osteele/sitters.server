Q = require 'q'
Firebase = require('firebase')
FirebaseTokenGenerator = require("firebase-token-generator")
tokenGenerator = new FirebaseTokenGenerator(process.env.FIREBASE_SECRET)

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
environmentFB = rootFB.child(process.env.ENVIRONMENT || 'development')

authenticateAs = (data, options) ->
  data ?= {}
  options ?= {}
  token = tokenGenerator.createToken(data, options)
  rootFB.auth token, (error, result) ->
    console.error 'error', error if error
    # console.info 'result', result unless error
  , (error) ->
    authenticateAs(data, options)

module.exports = {
  authenticateAs
  rootFB
  environmentFB

  fbOnP: (fb, eventType='value') ->
    deferred = Q.defer()
    fb.on eventType, (snapshot) ->
      deferred.resolve snapshot
    return deferred.promise

  fbOnceP: (fb, eventType='value') ->
    deferred = Q.defer()
    fb.once eventType, (snapshot) ->
      deferred.resolve snapshot
    return deferred.promise

  fbSetP: (fb, value) ->
    deferred = Q.defer()
    fb.set value, -> deferred.resolve()
    return deferred.promise

  requestsFB: environmentFB.child('request')
  messagesFB: environmentFB.child('message')

  accountsFB: environmentFB.child('account')
  familiesFB: environmentFB.child('family')
  sittersFB: environmentFB.child('sitter')
}
