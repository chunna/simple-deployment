#!/bin/bash -x

if [[ -s "$HOME/.rvm/scripts/rvm" ]] ; then
  source "$HOME/.rvm/scripts/rvm"
elif [[ -s "/usr/local/rvm/scripts/rvm" ]] ; then
  source "/usr/local/rvm/scripts/rvm"
else
  printf "ERROR: An RVM installation was not found.\n"
fi

# We're going to continue by installing Ruby and Bundler
rvm install ruby
rvm --default use ruby
gem install bundler --no-rdoc --no-ri

# Add in some additional software repositories for Passenger, a Ruby application server which integrates with Nginx
sudo yum install -y epel-release yum-utils
sudo yum-config-manager --enable epel

sudo yum install -y pygpgme
sudo curl --fail -sSLo /etc/yum.repos.d/passenger.repo https://oss-binaries.phusionpassenger.com/yum/definitions/el-passenger.repo
# Install Nginx, our webserver, and Passenger
sudo yum install -y nginx passenger

# To configure Passenger, we need to uncomment three lines in the Passenger configuration file - sed comes in handy for this
sudo sed -i "s/"#passenger_root"/"passenger_root"/g" /etc/nginx/conf.d/passenger.conf
sudo sed -i "s/"#passenger_ruby"/"passenger_ruby"/g" /etc/nginx/conf.d/passenger.conf
sudo sed -i "s/"#passenger_instance_registry_dir"/"passenger_instance_registry_dir"/g" /etc/nginx/conf.d/passenger.conf

# Here we setup a new user on the instance, which will be the user account that the app runs under. We'll call it sinatraapp
# For security reasons we won't add this user to the sudoers list
sudo useradd sinatraapp
sudo mkdir -p ~sinatraapp/.ssh
touch $HOME/.ssh/authorized_keys
sudo sh -c "cat $HOME/.ssh/authorized_keys >> ~sinatraapp/.ssh/authorized_keys"
sudo chown -R sinatraapp: ~sinatraapp/.ssh
sudo chmod 700 ~sinatraapp/.ssh
sudo sh -c "chmod 600 ~sinatraapp/.ssh/*"

# Let's create a folder for the app to reside in, and change the ownership over to our new account
sudo mkdir -p /var/www/sinatraapp
sudo chown sinatraapp: /var/www/sinatraapp
