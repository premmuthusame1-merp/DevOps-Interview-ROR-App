#!/bin/sh
set -e

echo "bundle installation"
bundle check || bundle install

echo "database setup"
bundle exec rails db:prepare

if [ -f tmp/pids/server.pid ]; then
  rm tmp/pids/server.pid
fi

exec "$@"
