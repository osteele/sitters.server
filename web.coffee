require './worker'

express = require("express")
app = express()
app.use express.logger()

app.get '/', (request, response) ->
  response.send 'Go home!'

app.get '/ping', (request, response) ->
  response.send 'OK'

port = process.env.PORT || 5000
app.listen port, () ->
  console.log "Listening on #{port}"
