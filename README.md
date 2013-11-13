# Installation

    brew install node
    brew install postgresql
    npm install

    psql -d postgres -c 'create database sitters'
    psql -d postgres -c 'create user sitters'

    ./bin/create_demo_rows

# Running

    coffee worker.coffee

# Contributing

SQL style: http://www.craigkerstiens.com/2012/11/17/how-i-write-sql/
