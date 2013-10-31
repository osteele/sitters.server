express = require("express")
app = express()
app.use(express.logger())

app.get '/', (request, response) ->
  response.send 'Go home!'

port = process.env.PORT || 5000
app.listen port, () ->
  console.log "Listening on #{port}"
