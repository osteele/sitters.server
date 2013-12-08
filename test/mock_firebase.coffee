FirebaseState =
  roots: {}
  events:
    added: {}
    deleted: {}
    changed: {}
  eventHandlers: []
  onServerSync: []
  nextGuid: 0

class Firebase
  constructor: (url) ->
    @url = url.replace(/\/$/, '')

  auth: ->

  child: (name) -> new Firebase([@url.replace(/\/$/, ''), name].join('/'))

  on: (eventType, callback, cancelCallback, context) ->
    FirebaseState.eventHandlers.push {eventType, url:@url, callback, context}
    if value = @_get()
      FirebaseState.newHandlers.push {eventType, url:@url, callback, context, value}
    return callback

  push: (value, onComplete) ->
    guid = "-GUID-#{FirebaseState.nextGuid += 1}"
    child = @child(guid)
    child.set value
    FirebaseState.onServerSync.push {onComplete} if onComplete
    FirebaseState.events.push {eventType:'child_added', url:@url, value}
    return child

  remove: (onComplete) ->
    @set null, onComplete

  _get: ->
    value = FirebaseState.roots
    components = [@url.replace(/\/\/.*/, '')].concat @url.replace(/.*?\/\//, '').split('/')
    console.log 'get', components
    for component in components
      return unless value
      value = value[component]

  set: (value, onComplete) ->
    setValue @url, value
    FirebaseState.onServerSync.push {onComplete} if onComplete

  toString: -> @url

getValueAt = (url, create=false) ->
  components = [@url.replace(/\/\/.*/, '')].concat @url.replace(/.*?\/\//, '').split('/')
  # console.log 'set', components, name
  parentValue = FirebaseState.root
  path = []
  for component in components
    path.push component
    value = parentValue[component]
    if create and not value?
      value = parentValue[component] = {}
      FirebaseState.events.push type:'create', url:path[0] + '//' + path.slice(1).join('/')
    parentValue = value
  return value

# Change the value at url to value, creating ancestors as necessary.
# Create value events (but not child_changed, child_removed, or child_moved)
# for this node.
# Create a child_added event for its parent.
# Returns true if value at url changed.
setValueAt = (url, value) ->
  value = null if typeof value == 'object' and Object.keys(value).length == 0
  parentUrl = url.replace(/[^\/]+$/, '')
  throw new Error("unimplemented: set root value") if parentUrl == url
  parentValue = getValueAt(parentUrl, value != null)
  return if parentValue == null
  name = url.replace(/.+\//, '')
  currentValue = parentValue[name]
  switch
    when currentValue == value
      return false
    when currentValue == null
      parentValue[name] = value
      postCreateEvents url, value
      FirebaseState.events.push type:'create', url
    when value == null
      if Object.keys(parentValue).length == 1
        setValueAt parentUrl, null
      else
        delete parentValue[name]
        FirebaseState.events.push type:'delete', url
    when typeof currentValue == 'object' and typeof value == 'object'
      changed = false
      for k of currentValue
        unless k of value
          changed = setValueAt(url + '/' + k, null) or changed
      for k, v of value
        changed = setValueAt(url + '/' + k, v) or changed
      FirebaseState.events.push type:'change', url if changed
      return changed
    when typeof currentValue == 'object'
      # replace object by non-object
      postDeleteEvents url, value
      parentValue[name] = value
      FirebaseState.events.push type:'change', url
    when typeof value == 'object'
      # replace non-object by object
      parentValue[name] = value
      FirebaseState.events.push type:'change', url
      postCreateEvents url, value
    else
      # replace one non-object by another
      parentValue[name] = value
      FirebaseState.events.push type:'change', url
  return true

postCreateEvents = (url, value) ->
  FirebaseState.events.push type:'create', url
  for k, v of value
    postCreateEvents url + '/' + k, v

postDeleteEvents = (url, value) ->
  FirebaseState.events.push type:'delete', url
  for k, v of value
    postDeleteEvents url + '/' + k, v

class DataSnapshot
  constructor: (url, value) ->
    @_name = url.replace(/^.+\./, '')
    @_value = value

  name: -> @name

  val: -> @value

Firebase.mock =
  simulateServerSync: ->
    while callback = FirebaseState.onServerSync.shift()
      callback.onComplete.call(null, null)

  run: ->
    # while FirebaseState.newHandlers.length or FirebaseState.events.length or FirebaseState.onServerSync.length
    #   while handler = FirebaseState.newHandlers.shift()
    #     {eventType, callback, context, url, value} = handler
    #     switch eventType
    #       when 'value'
    #         snapshot = new DataSnapshot(url, value)
    #         callback.call(context, snapshot)
    #       when 'child_added'
    #         for k, v of value
    #           snapshot = new DataSnapshot(url + '/' + k, v)
    #           callback.call(context, snapshot)
    #   while event = FirebaseState.events.shift()
    #     {type, url} = event
    #     invokeHandlersFor = (url, handlerType, includeAncestors=false) ->
    #       snapshot = null
    #       for handler in FirebaseState.eventHandlers
    #         {eventType, url:handlerPath, callback, context, added}
    #         if eventType == handlerType and handlerPath == url and not added
    #           snapshot ?= new DataSnapshot(getValueAt(url), value)
    #           callback.call(context, snapshot)
    #       if includeAncestors and m = url.match(/^(.+\/\/.+)\/.+/)
    #         invokeHandlersFor m[1], handlerType, true
    #     # Invoke value handlers for this node and its ancestors.
    #     invokeHandlersFor url, 'value', true
    #     switch type
    #       when 'create'
    #         invokeHandlersFor url, 'child_added', true
    #         # Invoke child_added handlers for this node's parent.
    #         # TODO pass the prevChildName argument to child_added
    #         # TODO call child_changed handlers.
    #       when 'delete'
    #         # Invoke value handlers for this node and its ancestors.
    #         # Invoke child_removed handlers for this node's parent.
    #   # @simulateServerSync()

module.exports = Firebase
