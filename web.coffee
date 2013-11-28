require('dotenv').load()
require './worker'

Winston = require 'winston'
logger = Winston.loggers.add 'web', console:{colorize:true, label:'web'}

express = require("express")
app = express()
app.use express.logger()

app.get '/', (request, response) ->
  response.send 401

app.get '/health', (request, response) ->
  response.send 'OK'

app.get '/ping', (request, response) ->
  response.send 'OK'

port = process.env.PORT || 5000
app.listen port, () ->
  logger.info "Listening on #{port}"
