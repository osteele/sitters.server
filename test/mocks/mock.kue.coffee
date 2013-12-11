class Queue
  constructor: ->
    @resetJobs()
    @callbacks = {}

  create: (type, data) ->
    return {
      save: (callback) =>
        @inactive.push {type, data}
        setTimeout (-> callback?()), 1
    }

  process: (type, callback) ->
    (@callbacks[type] ?= []).push callback

  activeCount: (callback) ->
    setTimeout (=> callback null, @active.length), 1

  inactiveCount: (callback) ->
    setTimeout (=> callback null, @inactive.length), 1

  resetJobs: ->
    @active = []
    @inactive = []

  run: ->
    while @inactive.length
      do =>
        job = @inactive.shift()
        @active.push job
        for callback in (@callbacks[job.type] || [])
          callback job, (err) => @markJobDone job, err

  markJobDone: (job, err) ->
    index = @active.indexOf(job)
    @active.splice index, 1 if index >= 0
    throw err if err

module.exports =
  createQueue: ->
    new Queue

  redis:
    createClient: ->
