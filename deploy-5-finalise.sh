#!/bin/bash -x

# We just need the path to Ruby as used by the app account, so we can configure Passenger
PATHTORUBY="$(sudo -u sinatraapp -i passenger-config about ruby-command | grep -Po '(?<=Nginx : passenger_ruby ).*')"

# Here we create the configuration file for our app. For now, we'll just host it internally on localhost until everything is working, before making it available to the world
sudo touch /etc/nginx/conf.d/sinatraapp.conf
echo "server {" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf 
echo "  listen 80;" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf 
echo "  server_name localhost;" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf 
echo "  root /var/www/sinatraapp/public;" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf
echo "  passenger_enabled on;" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf
echo "  passenger_ruby "$PATHTORUBY";" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf 
echo "}" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf

# We need to restart the webserver, Nginx for the changes to apply
sudo service nginx restart

# Now, let's check that it's working
curl localhost

# Here we run into a problem. A code 500 Internal Server error. After double-checking all the file and folder permissions, and going over the configuration files again, it turned out the problem was SElinux denying access
# So we'll bring up the log, and in particular, the item for the restriction using cat and grep, and pipe this to audit2allow to generate a custom type enforcement module, which we will import to allow access
cd ~
sudo cat /var/log/audit/audit.log | grep nginx | grep denied | audit2allow -M mynginx
# Import the custom module
sudo semodule -i mynginx.pp

# The changes should take effect immediately, so a webserver restart shouldn't be necessary
# Let's test it out by requesting the website, and pipe the output into status.txt
curl localhost > status.txt
WEBSTATUS="$(cat status.txt)"
IP="$(curl -s 'http://ipinfo.io' | grep -Po '(?<="ip": ")[^"]*')"

# If the contents of status.txt matches what we expect to see (Hello World!), then it means it is working
if [ "$WEBSTATUS" == "Hello World!" ]; then
	echo "Successfully deployed on localhost"
	# Reconfigure Nginx to serve the web app externally by changing localhost in the configuration file with the IP address of the instance
	sudo sed -i "s/"'server_name localhost'"/"'server_name '$IP"/g" /etc/nginx/conf.d/sinatraapp.conf
	# Restart Nginx to apply the changes
	sudo service nginx restart
else
	echo "Failed to deploy on localhost"
fi
