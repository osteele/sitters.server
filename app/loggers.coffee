winston = require 'winston'

do ->
  if process.env.NODE_ENV == 'production' or process.env.CI
    # In production, log sql to stdout so that it's routed to consolidated logging
    loggerOptions = {console:{colorize:true, label:'sql'}}
  else
    # In development, route sql to a file so that it's out of the way but available via tail -f.
    loggerOptions = {console:{silent:true}, file:{filename:__dirname + '/../logs/sql.log', json:false}}
  winston.loggers.add 'sql', loggerOptions

module.exports = (name) ->
  winston.loggers.get(name) ?
    winston.loggers.add name, console:{colorize:true, label:name}
