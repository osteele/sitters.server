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
# LocalStrategy = require('passport-local').Strategy
# passport.use new LocalStrategy((username, password, done) ->
#   logger.log 'check', username, password
#   # done null, {user:username}
#   done null, false, {message: 'no'}
# )

passport.serializeUser (user, done) ->
  console.log 'serialize', user
  done null, user

passport.deserializeUser (obj, done) ->
  console.log 'deserialize', obj
  done null, obj

passport.use new GitHubStrategy {
    clientID: process.env.GITHUB_CLIENT_ID
    clientSecret: process.env.GITHUB_CLIENT_SECRET
    callbackURL: 'http://localhost:5000/auth/github/callback'
  }, (accessToken, refreshToken, profile, done) ->
    console.log 'GitHubStrategy'
    done null, {username:profile.username}


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
  app.use express.session(secret:'pmjTWbmydExed3AP6fqw')
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
  (req, res) ->
    console.log 'callback'
    res.redirect('/')

# app.get '/login', (req, res) ->
#   res.render('login', { user: req.user })

app.get '/logout', (req, res) ->
  req.logout()
  res.redirect('/')

ensureAuthenticated = (req, res, next) ->
  return next() if req.isAuthenticated()
  res.redirect '/login.html'

# app.all '*',
#   # passport.authenticate('github', failureRedirect: '/login.html'),
#   (req, res, next) ->
#     console.log 'auth'
#     return next()

app.get '/', ensureAuthenticated, (req, res) ->
  # res.send 401
  console.log 'root'
  res.send 'hello'

port = process.env.PORT || 5000
app.listen port, ->
  logger.info "Listening on #{port}"
