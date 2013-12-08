messages = []
requests = []
messageHandlers = {}
requestHandlers = []

processRequests = ->
  count = 0
  while request = requests.shift()
    count += 1
    onRequest(request) for onRequest in requestHandlers
  return count > 0

processMessages = ->
  count = 0
  while messages.length
    {userAuthId, message} = messages.shift()
    count += 1
    onMessage(message) for onMessage in (messageHandlers[userAuthId] ? [])
  return count > 0

module.exports =
  onMessageForAccount: (userAuthId, onMessage) ->
    (messageHandlers[userAuthId] ?= []).push onMessage

  onRequest: (onRequest) ->
    requestHandlers.push onRequest

  sendMessageToAccount: (userAuthId, message) ->
    messages.push {userAuthId, message}

  sendRequestToServer: (request) ->
    requests.push request

  mock:
    process: ->
      count = 0
      while processRequests() or processMessages()
        count += 1
      return count > 0
