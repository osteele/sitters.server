# Seven Sitters Server

[ ![Codeship Status for osteele/sitters.server](https://www.codeship.io/projects/68120b20-426a-0131-2e69-0aefc5d00e69/status?branch=master)](https://www.codeship.io/projects/10615)

## Setting up a Development Environment

Install [Homebrew](http://brew.sh).

Install dependencies (Mac OS X):

    brew install git node postgresql rabbitmq redis
    npm install

Configure git:

    git config branch.autosetuprebase always
    git config branch.master.rebase true
    ln bin/pre-push-hook .git/hooks/pre-push

Copy `.env.template` to `.env` and fill in the values:

    cp .env.template .env
    $EDITOR .env
    # fill in the value for FIREBASE_SECRET



## Running

Run the web server and workers; reload when any file changes:

    nodemon

Run a simulated client in another terminal:

    ./bin/client


## Developer Documentation

Run `grunt docs` to create source documentation in `./build/docs`.

Run `grunt watch:docs` to rebuild documentation as you save.

Environment variables are documented in `./env.template`.

Client -> Server requests are documented in `./lib/request-handlers.coffee`.
If the source documentation has been built, this is also documented in `./build/docs/lib/request-handlers.html`.

Server -> Client requests are documented in `./lib/messages.coffee`.
If the source documentation has been built, this is also documented in `./build/docs/lib/messages.html`.

Log into the [local RabbitMQ web dashboard](http://localhost:15672/#/queues/%2F/request) as guest/guest to see the job queue.


## Developer Guidelines

Code must pass `grunt lint`.

Document new environment variables in `./env.template`.

Match the style of the file you're editing. More specifically:

Style guides:

- SQL should follow [Craig Kerstiens’ guide](http://www.craigkerstiens.com/2012/11/17/how-i-write-sql/).
- Coffeescript should follow [the Polarmobile style guide](https://github.com/polarmobile/coffeescript-style-guide) with these exceptions and additions:
  - Max line length is 120 chars (not 80 chars). `grunt lint` is thus configured.
  - Use parens `f(x)` for functions invoked for value. Omit parens `f x` for transitive functions in statement position, invoked for effect.
  - Prefer single quote `'strings'` to double quote `"strings"` where there's no interpolated parameters.


## Service Dashboards

- [Firebase](https://sevensitters.firebaseio.com/) data synchronization
- [Heroku](https://dashboard.heroku.com/apps/sevensitters-api/resources) PaaS hosting
- [Papertrail](https://papertrailapp.com/systems/sevensitters-api/dashboard) consolidated log file (or `heroku addons:open papertrail`)
- [Rollbar](https://rollbar.com/project/5918/) exception monitoring (or `heroku addons:open rollbar`)


# Firebase Security Rules

To update the Firebase security rules for developemnt:

1. Edit `./config/firebase-development-rules.coffee`.
2. Shell `grunt compile-security-rules`
3. Upload the compiled rules:
    1. Visit https://sevensitters.firebaseio.com,
    2. click the Security icon,
    3. copy `./build/firebase-security-rules.json` into the text area,
    4. click "Save Rules".

To promote the development security rules to production:

1. Shell `grunt promote-firebase-rules`
2. Compile and deploy the rules as per steps #2 and #3 above.
