require('dotenv').load()
apn = require 'apn'
util = require 'util'

winston = require 'winston'
winston.loggers.add 'push', console: {colorize: true, label: 'push'}
logger = winston.loggers.get('push')

APNServers = do ->
  production = process.env.ENVIRONMENT == 'production'
  gatewayServer = if production then 'gateway.push.apple.com' else 'gateway.sandbox.push.apple.com'
  feedbackServer = if production then 'feedback.push.apple.com' else 'feedback.sandbox.push.apple.com'
  { gatewayServer, feedbackServer }
console.log APNServers
connectionOptions = {gateway: APNServers.gatewayServer}
apnConnection = new apn.Connection(connectionOptions)

apnFeedback = new apn.Feedback(batchFeedback: true, interval: 300, address: APNServers.feedbackServer)
apnFeedback.on 'feedback', (devices) ->
  devices.forEach (item) ->
    logger.info 'Delivery failure:', item.device, item.time
logger.info "Polling APN feedback at #{APNServers.feedbackServer}"

DefaultExpirationHours = 7 * 24

exports.pushMessageTo = (token, {alert, payload}) ->
  device = new apn.Device(token)
  note = new apn.Notification()
  note.expiry = Math.floor(Date.now() / 1000) + 3600 * DefaultExpirationHours
  note.badge = 1
  note.alert = alert
  note.payload = payload
  logger.info 'Push to', token, "alert=#{util.inspect(alert)}"
  apnConnection.pushNotification note, device
