# Installation

    brew install node
    brew install postgresql
    npm install

    psql -d postgres -c 'create database sitters'
    psql -d postgres -c 'create user sitters'

# Running

    coffee worker.coffee
