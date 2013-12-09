require 'coffee-errors'
Q = require 'q'
_ = require 'underscore'
should = require 'should'
sinon = require 'sinon'

mockFirebase = require './mock_firebase'
mockMessageBus = require './mock_message_bus'

require('./mock_requires')
  firebase: mockFirebase
  'firebase-token-generator': mockFirebase.mock.TokenGenerator
  './message_bus': mockMessageBus
  './lib/message_bus': mockMessageBus
  rollbar:
    init: ->
    reportMessage: ->
    handleError: (err, cb) -> throw err
  stripe: -> {}
  apn: require './mock_apn'

models = require '../lib/models'
workers = require '../workers'
{sequelize} = models

Client = require '../lib/client'
createClientP = (userId) ->
  models.User.find(userId).then (user) ->
    new Client(user).run()

# Keep processing messages until they're done. Wait 100ms for database connections to clear.
# TODO call every 10ms with a timeout of 100ms since the last message
processMessagesP = ->
  mockMessageBus.mock.process() and Q.delay(100).then(-> processMessagesP())

describe 'invitations', ->
  beforeEach (done) ->
    sequelize.execute("DELETE FROM change_log").then -> done()

  it 'should round trip an add sitter invitation', (done) ->
    createClientP(1).then (client) ->
      client.sendRequestP('addSitter', sitterId:3, delay:0)
      .then(-> processMessagesP())
      .then(-> Q.delay(100))
      .then(-> models.Invitation.count where:{status:'accepted'})
      .then((n) -> n.should.eql 1)
      .done -> done()
