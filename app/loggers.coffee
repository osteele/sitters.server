winston = require 'winston'

env = process.env.NODE_ENV || 'development'
log_level = process.env.LOG_LEVEL

loggingOptionsFor = (name) ->
  switch env
    when 'development'
      {console:{label:name, level:log_level || 'info', colorize:true}}
    when 'test'
      {console:{label:name, level:log_level || 'error', timestamp:true}}
    when 'production'
      {console:{label:name, level:log_level || 'info'}}
    else
      throw new Exception("Unknown environment: #{env}")

switch env
  # In development, route sql to a file so that it's out of the way but available via `tail -f`.
  when 'development'
    winston.loggers.add 'sql',
      console : {label:'sql', level:'error'}
      file    : {filename:__dirname + '/../logs/sql.log', json:false}
  else
    winston.loggers.add 'sql',
      console : {label:'sql', level:'error'}

module.exports = (name) ->
  return winston.loggers.get(name, loggingOptionsFor(name))
