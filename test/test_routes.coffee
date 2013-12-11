require('dotenv').load()
process.env.NODE_ENV = 'test'
require 'coffee-errors'
request = require 'supertest'
app = require '../server'

describe 'index', () ->
  it 'serves html', (done) ->
    request(app)
      .get('/')
      .expect('Content-Type', /^text\/html;/)
      .expect(200, done)

describe 'server', () ->
  it 'responds to /ping', (done) ->
    request(app)
      .get('/ping')
      .expect(200, done)

  it 'responds to /health', (done) ->
    request(app)
      .get('/health')
      .expect(200, done)
