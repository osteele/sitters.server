#!/usr/bin/env coffee

Firebase = require('firebase')
rootFB = new Firebase('https://sevensitters.firebaseIO.com/')
requestFB = rootFB.child('request')

requestFB.push {requestType: 'addSitter', accountKey: 'facebook/511404287', parameters: {familyId: 1, sitterId: 2}},
  -> process.exit()
