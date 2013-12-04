# Generic utilities

# This is a special-case approved exception to the coding guideline rule not to extend
# native objects.
Object.defineProperty Object.prototype, 'tap',
  value: (fn) ->
    fn.call this
    return this
  enumerable: false
