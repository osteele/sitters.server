# Build Status

![](https://www.codeship.io/projects/68120b20-426a-0131-2e69-0aefc5d00e69/status?branch=master)

# Setting up a Development Environment

Install [Homebrew](http://brew.sh).

Install dependencies (Mac OS X):

    brew install git node postgresql redis
    npm install

Configure git:

    git config branch.autosetuprebase always
    git config branch.master.rebase true
    ln bin/pre-push-hook .git/hooks/pre-push

Copy `.env.template` to `.env` and fill in the values:

    cp .env.template .env
    $EDITOR .env
    # fill in value for FIREBASE_SECRET

Create and initialize the database.

    npm run initialize-database


# Running

Run the web server and workers:

    coffee server.coffee

Run a simulated client in another terminal:

    ./bin/client


# Developer Documentation

Run `grunt docs` to create source documentation in `./build/docs`.

Run `grunt watch:docs` to rebuild documentation as you save.

Environment variables are documented in `./env.template`.

Client -> Server requests are documented in `./lib/request-handlers.coffee`.
If the source documentation has been built, this is also documented in `./build/docs/lib/request-handlers.html`.

Server -> Client requests are documented in `./lib/messages.coffee`.
If the source documentation has been built, this is also documented in `./build/docs/lib/messages.html`.


# Developer Guidelines

Code must pass `grunt lint`.

Document new environment variables in `./env.template`.

Match the style of the file you're editing. More specifically:

Style guides:

- SQL should follow [Craig Kerstiens’ guide](http://www.craigkerstiens.com/2012/11/17/how-i-write-sql/).
- Coffeescript should follow [the Polarmobile style guide](https://github.com/polarmobile/coffeescript-style-guide) with these exceptions and additions:
  - Max line length is 120 chars (not 80 chars). `grunt lint` is thus configured.
  - Use parens `f(x)` for functions invoked for value. Omit parens `f x` for transitive functions in statement position, invoked for effect.
  - Prefer single quote `'strings'` to double quote `"strings"` where there's no interpolated parameters.


# Service Dashboards

- [Firebase](https://sevensitters.firebaseio.com/) data synchronization
- [Heroku](https://dashboard.heroku.com/apps/sevensitters-api/resources) PaaS hosting
- [Papertrail](https://papertrailapp.com/systems/sevensitters-api/dashboard) consolidated log file (or `heroku addons:open papertrail`)
- [Rollbar](https://rollbar.com/project/5918/) exception monitoring (or `heroku addons:open rollbar`)
