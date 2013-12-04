# Installation

    brew install node postgresql redis
    npm install

    psql -d postgres -c 'create database sitters'
    psql -d postgres -c 'create user sitters'

Copy .env.template to .env and fill in the values.

    ./bin/populate-demo-sitters
    ./bin/update-triggers


# Running

Run the web server and workers:

    coffee server.coffee

Run a simulated client in another terminal:

    ./bin/client


# Developer Documentation

Run `grunt docs` to create API documentation in `./build/docs`.

Run `grunt watch:docs` to rebuild documentation as you save.

Client -> Server requests are documented in `./worker.coffee`.
If the documentation is built, this is also in `/build/docs/worker.html`.


# Developer Guidelines

Code must pass `grunt lint`.

Match the style of the file you're editing. More specifically:

Style guides:

- [SQL style](http://www.craigkerstiens.com/2012/11/17/how-i-write-sql/)
- [Coffeescript style](https://github.com/polarmobile/coffeescript-style-guide) except:
  - Max line length is 120 chars (not 80 chars). `grunt lint` is thus configured.
  - Use parens `f(x)` for functions invoked for value. Omit parens `f x` for transitive functions in statement position, invoked for effect.
  - Prefer single quote `'strings'` to double quote `"strings"` where there's no interpolated parameters.


# Service Dashboards

- [Firebase](https://sevensitters.firebaseio.com/) data synchronization
- [Heroku](https://dashboard.heroku.com/apps/sevensitters-api/resources) PaaS hosting
- [Papertrail](https://papertrailapp.com/systems/sevensitters-api/dashboard) consolidated log file (or `heroku addons:open papertrail`)
- [Rollbar](https://rollbar.com/project/5918/) exception monitoring (or `heroku addons:open rollbar`)
