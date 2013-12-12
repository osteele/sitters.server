#!/usr/bin/env coffee

# Web server. Running this also includes workers, so that everything can be run in one process
# for development simplicity and to reduce hosting costs prior to trial.

#
# Imports
# --

require('dotenv').load()
kue = require './app/integrations/kue'
logger = require('./app/loggers')('server')
require './app/workers'

# Set the process's title so it's easier to find in `ps`, # `top`, Activity Monitor, and so on.
process.title = 'sitters.server'


#
# Configure Auth
# --

passport = require 'passport'
GitHubStrategy = require('passport-github').Strategy
GithubAdminIds = (process.env.GITHUB_ADMIN_IDS || process.env.USER).split(/,/)

passport.serializeUser (user, done) ->
  done null, user

passport.deserializeUser (obj, done) ->
  done null, obj

passport.use new GitHubStrategy {
  clientID: process.env.GITHUB_CLIENT_ID
  clientSecret: process.env.GITHUB_CLIENT_SECRET
  callbackURL: process.env.GITHUB_CALLBACK_URL
}, (accessToken, refreshToken, profile, done) ->
  username = profile.username
  roles = if username in GithubAdminIds then ['admin'] else []
  done null, {username, roles}

requireAdmin = (req, res, next) ->
  return res.redirect '/login' unless req.isAuthenticated()
  return res.send 401 unless 'admin' in req.user.roles
  return next()


#
# Server Application
# --

express = require("express")
app = express()

RedisStore = require('connect-redis')(express)
sessionStore = do ->
  url = require("url").parse(process.env.REDISTOGO_URL || 'redis://127.0.0.1:6379/')
  options =
      host: url.host.replace(/:\d+/, '')
      port: Number(url.port)
      pass: (url.auth || '').split(':')[1]
  new RedisStore(options)
sessionSecret = process.env.SESSION_SECRET

app.set 'views', __dirname + '/views'
app.set 'view engine', 'jade'

app.configure ->
  app.use express.logger() if process.env.NODE_ENV == 'production'
  app.use express.cookieParser()
  app.use express.urlencoded()
  app.use express.json()
  app.use express.methodOverride()
  app.use express.session store:sessionStore, secret:sessionSecret
  app.use passport.initialize()
  app.use passport.session()
  app.use app.router
  app.use express.static(__dirname + '/public')
  app.use requireAdmin
  app.use '/jobs', kue.app
  app.use (err, req, res, next) ->
    console.error err.stack
    next err

app.get '/health', (request, response) ->
  response.send 'OK'

# The client pings this to awaken the server after dropping a request in the Firebase queue.
app.get '/ping', (request, response) ->
  response.send 'OK'

app.get '/simulate-error', (request, response) ->
  response.send 401 if process.env.NODE_ENV == 'production'
  throw new Error('simulated server error')


#
# Login
# --

app.get '/auth/github',
  passport.authenticate('github'),
  (req, res) -> # not called

app.get '/auth/github/callback',
  passport.authenticate('github', failureRedirect: '/login'),
  (req, res) -> res.redirect '/admin'

app.get '/login', (req, res) ->
  res.render 'login'

app.get '/logout', (req, res) ->
  req.logout()
  res.redirect '/admin'


#
# User Pages
# --

app.get '/', (req, res) ->
  res.render 'index'


#
# Admin Pages
# --

app.get '/admin', requireAdmin, (req, res) ->
  res.render 'admin'


#
# Start Server
# --

if require.main == module
  port = process.env.PORT || 5000
  app.listen port, ->
    logger.info "Listening on #{port}"

module.exports = app
