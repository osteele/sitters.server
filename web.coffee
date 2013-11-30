require('dotenv').load()
require './worker'

#
# Logging
#

Winston = require 'winston'
logger = Winston.loggers.add 'web', console:{colorize:true, label:'web'}


#
# Auth
#

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
  return res.redirect '/login.html' unless req.isAuthenticated()
  return res.send 401 unless 'admin' in req.user.roles
  return next()


#
# Application
#

express = require("express")
app = express()
app.configure ->
  app.use express.logger()
  app.use express.cookieParser()
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.session(secret: process.env.SESSION_SECRET || 'pmjTWbmydExed3AP6fqw')
  app.use passport.initialize()
  app.use passport.session()
  app.use app.router
  app.use express.static(__dirname + '/public')

app.get '/health', (request, response) ->
  response.send 'OK'

app.get '/ping', (request, response) ->
  response.send 'OK'


#
# Login
#

app.get '/auth/github',
  passport.authenticate('github'),
  (req, res) -> # not called

app.get '/auth/github/callback',
  passport.authenticate('github', failureRedirect: '/login.html'),
  (req, res) -> res.redirect('/')

# app.get '/login', (req, res) ->
#   res.render('login', { user: req.user })

app.get '/logout', (req, res) ->
  req.logout()
  res.redirect('/')

# app.all '*',
#   # passport.authenticate('github', failureRedirect: '/login.html'),
#   (req, res, next) ->
#     console.log 'auth'
#     return next()

app.get '/', requireAdmin, (req, res) ->
  # res.send 401
  res.send 'hello'

port = process.env.PORT || 5000
app.listen port, ->
  logger.info "Listening on #{port}"
