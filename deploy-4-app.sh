#!/bin/bash -xl

# In this script we've logged in using the newly created account which will run the app
# This is necessary in order to configure the software environment wth Ruby and Bundle properly
rvm --default use ruby
cd /var/www/sinatraapp
git clone git://github.com/tnh/simple-sinatra-app.git .
mkdir -p /var/www/sinatraapp/public
# Using sudo with bundle install is not recommended, since there are steps performed by bundler which need to be run under the current user (http://bundler.io/v1.11/man/bundle-install.1.html)
bundle install --path vendor/bundle
