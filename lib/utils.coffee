exports.camelCaseToSnakeCase = (string) -> string.replace(/[A-Z]/g, (c) -> '-' + c.toLowerCase())
exports.trainCaseToCamelCase = (string) -> string.replace(/-(.)/g, (__, c) -> c.toUpperCase())

Object.defineProperty Object.prototype, 'tap',
  value: (fn) ->
    fn.call this
    return this
  enumerable: false
