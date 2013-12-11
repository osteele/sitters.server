class Queue
  constructor: ->
    @resetJobs()
    @callbacks = {}

  create: (type, data) ->
    return {
      save: => @inactive.push {type, data}
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
    while job = @inactive.shift()
      @active << job
      for callback in (@callbacks[job.type] || [])
        # console.log 'callback', callback, job.data
        callback job, (err) => @markJobDone job, err

  markJobDone: (job, err) ->
    index = @active.indexOf
    @active.splice index, 1 if index >= 0
    throw err if err

module.exports =
  createQueue: ->
    new Queue

  redis:
    createClient: ->
