Q = require 'q'
Firebase = require('firebase')
FirebaseTokenGenerator = require("firebase-token-generator")
TokenGenerator = new FirebaseTokenGenerator(process.env.FIREBASE_SECRET)

FirebaseRoot = new Firebase('https://sevensitters.firebaseIO.com/')
EnvironmentFB = FirebaseRoot.child(process.env.ENVIRONMENT || 'development')

authenticateAs = (data={}, options={}) ->
  token = TokenGenerator.createToken(data, options)
  FirebaseRoot.auth token, (error, result) ->
    console.error 'error', error if error
  , (error) ->
    authenticateAs(data, options)

module.exports = {
  FirebaseRoot
  EnvironmentFB

  authenticateAs

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

  fbRemoveP: (fb) ->
    deferred = Q.defer()
    fb.remove -> deferred.resolve()
    return deferred.promise

  fbSetP: (fb, value) ->
    deferred = Q.defer()
    fb.set value, -> deferred.resolve()
    return deferred.promise

  # Request and response queues
  RequestFB: EnvironmentFB.child('request')
  DeprecatedMessageFB: EnvironmentFB.child('message')
  MessageFB: EnvironmentFB.child('message/user/auth')

  # Entities
  AccountFB: EnvironmentFB.child('account')
  FamilyFB: EnvironmentFB.child('family')
  SitterFB: EnvironmentFB.child('sitter')
}
