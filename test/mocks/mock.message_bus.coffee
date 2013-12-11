activeMessages = null
inactiveMessages = null
messageHandlers = {server:[]}

messageDone = (message) ->
  index = activeMessages.indexOf(message)
  activeMessages.splice index, 1 if index >= 0

processMessages = ->
  while inactiveMessages.length
    message = inactiveMessages.shift()
    activeMessages.push message
    {recipient, data} = message
    for callback in (messageHandlers[recipient] ? [])
      callback data, -> messageDone message

resetMessages = ->
  activeMessages = []
  inactiveMessages = []

resetMessages()

module.exports =
  onMessageForAccount: (accountId, callback) ->
    (messageHandlers[accountId] ?= []).push callback

  onServerRequest: (callback) ->
    messageHandlers.server.push callback

  sendMessageToAccount: (accountId, data) ->
    inactiveMessages.push {recipient:accountId, data}

  sendRequestToServer: (data) ->
    inactiveMessages.push {recipient:'server', data}

  activeCount: ->
    # for {recipient} in activeMessages
    #   console.log 'pending', recipient
    return activeMessages.length

  resetMessages: resetMessages

  run: processMessages
