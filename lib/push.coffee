require('dotenv').load()
apn = require 'apn'
path = require 'path'
util = require 'util'

winston = require 'winston'
winston.loggers.add 'APNS', console: {colorize: true, label: 'APNS'}
logger = winston.loggers.get('APNS')

APNErrorText =
  0: 'No errors encountered'
  1: 'Processing error'
  2: 'Missing device token'
  3: 'Missing topic'
  4: 'Missing payload'
  5: 'Invalid token size'
  6: 'Invalid topic size'
  7: 'Invalid payload size'
  8: 'Invalid token'
  10: 'Shutdown'
  255: 'None (unknown)'

CertificateDirectory = path.join(__dirname, '..', 'config')
DefaultExpirationHours = 7 * 24

APNServers = do ->
  production = process.env.ENVIRONMENT == 'production'
  gatewayServer = if production then 'gateway.push.apple.com' else 'gateway.sandbox.push.apple.com'
  feedbackServer = if production then 'feedback.push.apple.com' else 'feedback.sandbox.push.apple.com'
  { gatewayServer, feedbackServer }

connectionOptions = {
  cert: path.join(CertificateDirectory, 'apns-dev-cert.pem')
  key: path.join(CertificateDirectory, 'apns-dev-key.pem')
  gateway: APNServers.gatewayServer
}
console.log  connectionOptions
connection = new apn.Connection(connectionOptions)
connection.on 'connected', -> logger.info "Connected"
connection.on 'transmitted', (notification, device) ->
  logger.info "Notification transmitted to #{device.token.toString('hex')}"
connection.on 'transmissionError', (errCode, notification, device) ->
  logger.error "Transmission error ##{errCode} (#{APNErrorText[errCode]}) for device", device.token.toString('hex')
connection.on 'timeout', -> logger.error "Timeout"
connection.on 'disconnected', -> logger.info "Disconnected"
connection.on 'socketError', (err) -> logger.error err

feedback = new apn.Feedback(batchFeedback: true, interval: 300, address: APNServers.feedbackServer)
feedback.on 'feedback', (devices) ->
  devices.forEach (item) ->
    logger.info 'Delivery failure', item.device.token.toString('hex'), item.time
feedback.on 'feedbackError', (err) -> logger.error err
logger.info "Polling APN feedback at #{APNServers.feedbackServer}"

pushMessageTo = (token, {alert, payload}) ->
  device = new apn.Device(token)
  note = new apn.Notification()
  note.expiry = Math.floor(Date.now() / 1000) + 3600 * DefaultExpirationHours
  note.badge = 1
  note.alert = alert
  note.payload = payload
  logger.info "Notify token=#{token} alert=#{util.inspect(alert)}"
  # logger.info "Notify token=#{token} alert=#{util.inspect(alert)} payload=#{util.inspect(payload)}"
  connection.pushNotification note, device

module.exports = {
  connection
  feedback
  pushMessageTo
}
