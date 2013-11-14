Firebase = require('firebase')
Q = require 'Q'

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
environmentFB = rootFB
environmentFB = environmentFB.child(process.env.ENVIRONMENT) if process.env.ENVIRONMENT

module.exports = {
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
