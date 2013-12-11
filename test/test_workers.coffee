# Import test-related modules
# --
require('dotenv').load()
process.env.NODE_ENV = 'test'

require 'coffee-errors'
should = require 'should'
sinon = require 'sinon'

# Import non-test-specific modules
# --
Q = require 'q'
_ = require 'underscore'

# Define mocks. Do this before importing app modules that might require these.
# --
mockFirebase = require './mocks/mock.firebase'
mockMessageBus = require './mocks/mock.message_bus'

require('../lib/mock_requires')
  firebase: mockFirebase
  'firebase-token-generator': mockFirebase.mock.TokenGenerator
  './message_bus': mockMessageBus
  './lib/message_bus': mockMessageBus
  rollbar:
    init: ->
    reportMessage: ->
    handleError: (err, cb) -> throw err
  stripe: -> {}
  apn: require './mocks/mock.apn'

# Import (non-mocked) application modules.
# --
kue = require '../app/integrations/kue'
models = require '../app/lib/models'
workers = require '../app/workers'
{sequelize} = models

# Define test helpers
# --
Client = require '../app/lib/client'
createClientP = (userId) ->
  models.User.find(userId).then (user) ->
    new Client(user).run()

deleteJobsP = ->
  queue = workers.jobs
  Q.ninvoke(queue, 'active').then (jobs) ->
    console.log 'Deleting leftover kue jobs:', jobs.join(', ') if jobs.length
    Q.all jobs.map (jobId) -> Q.ninvoke kue.Job, 'remove', jobId

# Keep processing messages until they're done. Wait 100ms for database connections to clear.
# TODO call every 10ms with a timeout of 100ms since the last message
processMessagesP = ->
  queue = workers.jobs
  processed = mockMessageBus.mock.process()
  Q.spread [
    Q.ninvoke(queue, 'activeCount')
    Q.ninvoke(queue, 'inactiveCount')
  ], (active, inactive) ->
    # console.log 'activeCount', active, 'inactiveCount', inactive
    return Q.when(100).then(-> processMessagesP()) if active or inactive or processed
    return false

describe 'invitations', ->
  beforeEach (done) ->
    Q.all([
      sequelize.execute 'TRUNCATE change_log'
      sequelize.execute 'TRUNCATE invitations'
      deleteJobsP()
    ]).done -> done()

  it 'should round trip an add sitter invitation', (done) ->
    createClientP(1).then (client) ->
      client.sendRequestP('addSitter', sitterId:3, delay:0)
      .then(-> Q.delay(100))
      .then(-> processMessagesP())
      .then(-> models.Invitation.count where:{status:'accepted'})
      .then((n) -> n.should.eql 1)
      .done -> done()
