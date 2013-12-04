# Adaptor to kue.
# Modifies the default kue client to connect to redis instead of localhost, if `REDISTOGO_URL` is in the environment.

kue = require('kue')

kue.redis.createClient = ->
  require('redis-url').connect(process.env.REDISTOGO_URL || 'redis://:@127.0.0.1:6379/')

module.exports = kue
