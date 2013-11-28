# Installation

    brew install node postgresql
    npm install

    psql -d postgres -c 'create database sitters'
    psql -d postgres -c 'create user sitters'

Copy .env.template to .env and fill in the values.

    ./bin/populate-demo-sitters
    ./bin/update-triggers


# Running

    coffee worker.coffee


# Service Dashboards

- [Firebase](https://sevensitters.firebaseio.com/) data synchronization
- [Heroku](https://dashboard.heroku.com/apps/sevensitters-api/resources) PaaS hosting
- [Papertrail](https://papertrailapp.com/systems/sevensitters-api/dashboard) consolidated log file (or `heroku addons:open papertrail`)
- [Rollbar](https://rollbar.com/project/5918/) exception monitoring (or `heroku addons:open rollbar`)


# Contributing

SQL style: http://www.craigkerstiens.com/2012/11/17/how-i-write-sql/
