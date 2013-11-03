#!/usr/bin/env coffee

_ = require 'underscore'
Q = require 'q'
models = require '../models'
sitters = require '../data/sitters.json'

upsertSitter = Q.nbind models.Sitter.upsert, models.Sitter

promise = Q.all sitters.map (sitter) ->
  id = sitter.id
  data = _.extend {}, sitter
  delete data.id
  console.info 'Updating', id, sitter.name
  upsertSitter {id, data:{data:JSON.stringify(data)}}

promise
  .catch( (error) -> console.error error )
  .done ->
    process.exit()
