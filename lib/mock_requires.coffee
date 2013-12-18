# Override `require` to retrieve specified modules from a hash instead of
# the file system.
#
# Usage:
#
#     require('./path/to/mock_requires')({
#       fs: require('./path/to/mock-fs'),
#       './module_1': require('./path/to/mock-module-1'),
#       '../lib/module_2': require('./path/to/mock-module-1')
#     })
#
# Keys are paths that are relative to the path of the module that *first* requires
# mock_requires.

moduleModule = require 'module'
path = require 'path'

builtinRequire = moduleModule.prototype.require

mockModules = {}

mockRequire = (relpath) ->
  abspath = relpath
  abspath = arguments.callee.caller.resolve(relpath) if relpath.match(/^\.\.?\//)
  abspath = abspath.replace(/\.[^\.\/]+$/, '')
  # console.log 'intercepted', relpath, '->', abspath if mockModules[abspath]?
  mockModules[abspath] || builtinRequire.call(this, relpath)

moduleModule.prototype.require = mockRequire

defineMockModules = (map) ->
  dirname = path.dirname(module.parent.filename)
  for k, v of map
    k = path.join(dirname, k) if k.match(/^\.\.?\//)
    # console.log 'register', k
    mockModules[k] = v

module.exports = defineMockModules
