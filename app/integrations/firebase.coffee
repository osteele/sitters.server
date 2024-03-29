# Firebase shim. Defines app-specific message and entity paths, and adds Promise interface to Firebase API.

Q = require 'q'
Firebase = require('firebase')
FirebaseTokenGenerator = require('firebase-token-generator')
TokenGenerator = new FirebaseTokenGenerator(process.env.FIREBASE_SECRET)
logger = require('../loggers')('firebase')

firebaseRef = new Firebase('https://sevensitters.firebaseIO.com/')
EnvironmentFB = do ->
  prefix = process.env.FIREBASE_ENV || process.env.NODE_ENV || 'development'
  firebaseRef.child(prefix)

# Wrapper for `firebaseRef.auth`. Creates the token, authenticates with a handler to renews it when it expires.
authenticateAs = (data={}, options={}) ->
  token = TokenGenerator.createToken(data, options)
  firebaseRef.auth token, (error, result) ->
    logger.error 'error', error if error
    # will expire at result.expires * 1000
  , (error) ->
    logger.info "Renewing expired firebase authentication"
    authenticateAs data, options

module.exports = {
  firebaseRef
  EnvironmentFB

  authenticateAs

  # Promise adaptors for Firebase API
  # --

  fbOnP: (fb, eventType='value') ->
    deferred = Q.defer()
    fb.on eventType,
      (snapshot) -> deferred.resolve snapshot
      (err) -> deferred.reject err
    return deferred.promise

  fbOnceP: (fb, eventType='value') ->
    deferred = Q.defer()
    fb.once eventType,
      (snapshot) -> deferred.resolve snapshot
      (err) -> deferred.reject err
    return deferred.promise

  fbPushP: (fb, value) ->
    deferred = Q.defer()
    fb.push value, (err) -> if err then deferred.reject err else deferred.resolve()
    return deferred.promise

  fbRemoveP: (fb) ->
    deferred = Q.defer()
    fb.remove (err) -> if err then deferred.reject err else deferred.resolve()
    return deferred.promise

  fbSetP: (fb, value) ->
    deferred = Q.defer()
    fb.set value, (err) -> if err then deferred.reject err else deferred.resolve()
    return deferred.promise

  # Request and response queues
  # --
  requestsRef: EnvironmentFB.child('request')
  accountMessagesRef: EnvironmentFB.child('message/user/auth')

  # Entities
  # --
  sitterProfilesRef: EnvironmentFB.child('sitter')
  usersRef: EnvironmentFB.child('user')
}
