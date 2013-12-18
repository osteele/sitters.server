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
messageBus = require './mocks/mock.message_bus'

require('../lib/mock_requires')
  # node module mocks
  apn: require './mocks/mock.apn'
  firebase: mockFirebase
  'firebase-token-generator': mockFirebase.mock.TokenGenerator
  kue: require './mocks/mock.kue'
  rollbar:
    init: ->
    reportMessage: ->
    handleError: (err, cb) -> throw err
  stripe: -> {}
  # app module mocks
  '../app/lib/message_bus': messageBus


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
  {User} = models
  testUserAttrs =
    displayName : 'Test'
    email       : 'test-user@sevensitters.com'
    id          : userId
    role        : 'parent'
  User.findOrCreate({id:userId}, testUserAttrs).then (user) ->
    accountAttributes =
      user_id          : user.id
      provider_name    : 'facebook'
      provider_user_id : String(172347878787877)
    user.getAccounts().then((accounts) -> Account.create(accountAttributes) unless accounts.length)
    .then -> new Client(user).run()

# Keep processing messages until they're done.
processMessagesP = ->
  jobQueue = workers.jobs
  jobQueue.run()
  messageBus.run()
  Q.spread [
    Q.ninvoke(jobQueue, 'activeCount')
    Q.ninvoke(jobQueue, 'inactiveCount')
  ], (activeJobs, inactiveJobs) ->
    activeMessages = messageBus.activeCount()
    # console.log {'active jobs':activeJobs, 'inactive jobs':inactiveJobs, 'active messages':activeMessages}
    return Q.delay(100).then(-> processMessagesP()) if activeJobs or inactiveJobs or activeMessages

describe 'invitations', ->
  beforeEach (done) ->
    Q.all([
      sequelize.execute 'TRUNCATE change_log'
      sequelize.execute 'TRUNCATE invitations'
      workers.jobs.resetJobs()
      messageBus.resetMessages()
    ]).done -> done()

  it 'should round trip an add sitter invitation', (done) ->
    createClientP(1).then (client) ->
      client.sendRequestP('addSitter', sitterId:'70f81b13-baba-424b-855f-134553717a63', delay:0)
      .then(-> processMessagesP())
      .then(-> models.Invitation.count where:{status:'accepted'})
      .then((invitationCount) -> invitationCount.should.eql 1)
      .done -> done()
