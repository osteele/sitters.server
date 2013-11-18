Object.defineProperty Object.prototype, 'tap',
  value: (fn) ->
    fn.call this
    return this
  enumerable: false
