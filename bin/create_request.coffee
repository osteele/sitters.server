#!/usr/bin/env coffee
Firebase = require('firebase')
rootRef = new Firebase('https://sevensitters.firebaseIO.com/')
requestRef = rootRef.child('request')

requestRef.push {'requestType': 'addSitter', 'userId': 'facebook/511404287', 'familyId': '-J6vm9lvSXvyC_e5V43L', sitterId: 2}
