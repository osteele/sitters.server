Firebase = require('firebase')

rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
environmentFB = rootFB
environmentFB = environmentFB.child(process.env.ENVIRONMENT) if process.env.ENVIRONMENT

module.exports = {
  rootFB
  environmentFB

  requestsFB: environmentFB.child('request')
  messagesFB: environmentFB.child('message')

  accountsFB: environmentFB.child('account')
  familiesFB: environmentFB.child('family')
}
