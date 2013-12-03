# Installation

    brew install node postgresql redis
    npm install

    psql -d postgres -c 'create database sitters'
    psql -d postgres -c 'create user sitters'

Copy .env.template to .env and fill in the values.

    ./bin/populate-demo-sitters
    ./bin/update-triggers


# Running

    coffee worker.coffee # just the workers
    coffee web.coffee # workers and web server


# Develop

Run `grunt docs` to create API documentation in `./build/docs`.

Run `grunt watch:docs` to rebuild documentation as you save.

Style guides:

- [SQL style](http://www.craigkerstiens.com/2012/11/17/how-i-write-sql/)


# Service Dashboards

- [Firebase](https://sevensitters.firebaseio.com/) data synchronization
- [Heroku](https://dashboard.heroku.com/apps/sevensitters-api/resources) PaaS hosting
- [Papertrail](https://papertrailapp.com/systems/sevensitters-api/dashboard) consolidated log file (or `heroku addons:open papertrail`)
- [Rollbar](https://rollbar.com/project/5918/) exception monitoring (or `heroku addons:open rollbar`)
