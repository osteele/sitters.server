Q = require 'q'

class Queue
  constructor: ->
    @resetJobs()
    @handlers = []

  create: (data) ->
    @inactive.push {data}

  process: (handler) ->
    @handlers.push handler

  activeCount: ->
    return @active.length

  inactiveCount: ->
    return @inactive.length

  resetJobs: ->
    @active = []
    @inactive = []

  run: ->
    while @inactive.length
      do =>
        job = @inactive.shift()
        @active.push job
        for handler in @handlers
          handler job.data, (err) => @markJobDone job, err

  markJobDone: (job, err) ->
    index = @active.indexOf(job)
    @active.splice index, 1 if index >= 0
    throw err if err

queues = {}
getQueue = (queueName) ->
  queues[queueName] ?= new Queue

module.exports =
  create: (queueName, data) ->
    getQueue(queueName).create data
    return Q.delay(1)

  process: (queueName, handler) ->
    getQueue(queueName).process handler

  resetJobs: ->
    queue.resetJobs() for _, queue of queues

  run: ->
    queue.run() for _, queue of queues

  activeCount: ->
    return (queue.activeCount() for _, queue of queues).reduce ((a, b) -> a + b), 0

  inactiveCount: ->
    return (queue.inactiveCount() for _, queue of queues).reduce ((a, b) -> a + b), 0
