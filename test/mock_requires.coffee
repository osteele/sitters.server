moduleModule = require 'module'

mockModules = {}

requireWithoutMock = moduleModule.prototype.require

mockRequire = (path) ->
  mockModules[path] || requireWithoutMock.call(this, path)

Object.keys(requireWithoutMock).forEach (key) ->
  Object.define mockRequire, key,
    get: -> requireWithoutMock[key]
    set: (value) -> requireWithoutMock[key] = value

moduleModule.prototype.require = mockRequire

module.exports = (map) ->
  for k, v of map
    mockModules[k] = v
