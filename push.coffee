apn = require 'apn'

options = {gateway: 'gateway.sandbox.push.apple.com'}
apnConnection = new apn.Connection(options)

apnFeedback = new apn.Feedback(batchFeedback: true, interval: 300)
apnFeedback.on 'feedback', (devices) ->
  # console.log 'feedback', devices.length
  devices.forEach (item) ->
    console.log item.device, item.time;
    util.debug item

exports.pushMessageTo = (token, {alert, payload}) ->
  expirationHours = 24
  device = new apn.Device(token)
  note = new apn.Notification()
  note.expiry = Math.floor(Date.now() / 1000) + 3600 * expirationHours
  note.badge = 1
  note.alert = alert
  note.payload = payload
  apnConnection.pushNotification note, device

testPush = ->
  token = "[[redacted]]".replace(/\s/g, '')
  pushMessageTo token, alert: "\uD83D\uDCE7 \u2709 You have a new message", payload: {'messageFrom': 'Oliver'}
