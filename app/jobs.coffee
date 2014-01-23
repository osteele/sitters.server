Q = require 'q'
amqp = require 'amqp'

connectionReadyD = Q.defer()
connectionReadyP = connectionReadyD.promise

url = process.env.CLOUDAMQP_URL || "amqp://localhost"
connection = amqp.createConnection {url}
connection.on 'ready', ->
  return unless connectionReadyD
  connectionReadyD.resolve connection
  connectionReadyD = null

queuePs = {}

getQueueP = (queueName) ->
  return queuePs[queueName] if queueName of queuePs
  deferred = queuePs[queueName] = Q.defer()
  connectionReadyP.then (exchange) ->
    connection.queue queueName, {autoDelete: false, durable: true}, (queue) ->
      queue.bind '#' # catch all messages
      deferred.resolve queue
  return deferred.promise

module.exports =
  create: (queueName, data) ->
    connectionReadyP.then (connection) ->
      connection.publish queueName, data, {}, (error) ->
        console.error error if error

  process: (queueName, handler) ->
    getQueueP(queueName).then (queue) ->
      queue.subscribe {ack: true}, (data, headers, deliveryInfo, msg) ->
        handler data, ->
          msg.acknowledge()
