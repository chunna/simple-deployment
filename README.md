#Simple Deployment
*A simple Ruby/Sinatra App deployment from scratch.*

This is a simple deployment for a Ruby/Sinatra app, in response to [this code test](https://github.com/tnh/simple-sinatra-app "https://github.com/tnh/simple-sinatra-app").
It deploys a CentOS instance on Amazon Web Services, fully updated and configured to run Nginx and Passenger. 

All this from invoking one command:

```sh
deploy-1-instance.sh
```

##Requirements
This script depends on the AWS CLI and OpenSSH, and assumes you have these configured already. It is intended to run from Linux, but will probably work on UNIX and MacOS too, provided the above mentioned tools are available.

Need the AWS CLI tools? Get them [here](https://aws.amazon.com/cli/ "https://aws.amazon.com/cli/").

OpenSSH is generally available on most platforms by default. If not, check your package manager.

Additionally, you will need an account on AWS. If you don't currently have one, you can sign up for an account at [Amazon's AWS portal](https://aws.amazon.com/ "https://aws.amazon.com/"). The deployed instance (t2.micro) qualifies for Amazon's free tier, so no costs are necessary to see this in action.

##Installation
Ensure you have the AWS CLI tools installed and configured with an appropriate Access Key tied to your AWS account. For more information about configuring the AWS Command Line Interface, follow the guide for [Getting Set Up](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-set-up.html).

Next you'll need a copy of the script files. There are actually five of them:

* deploy-1-instance.sh
* deploy-2-rvm.sh
* deploy-3-nginx.sh
* deploy-4-app.sh
* deploy-5-finalise.sh

You can download a ZIP file containing all files from GitHub at the [project page](https://github.com/chunna/simple-deployment "https://github.com/chunna/simple-deployment"), or if you have `git` installed on your system, you can clone the repository from the command line to the folder of your choice:

```sh
$ git clone git://github.com/chunna/simple-deployment.git <folder of your choice>
```
Once you have the files, ensure the script files (*.sh) are executable. You can do this with the command below. Just make sure you are already in the folder where the files have been cloned to if you used `git`; or unzipped to, if you downloaded a ZIP file of the scripts.

```sh
$ chmod u+x *.sh
```

##Usage
Ready? From the command line, enter:

```sh
$ ./deploy-1-instance.sh
```
##What this script does
Let's break this down.

When you execute the script, the following steps are made:
* An EC2 instance is provisioned
* RVM, Ruby, Nginx and Passenger are installed
* The application files are downloaded from GitHub
* The script configures the app to be served via Nginx and Passenger
* Test and verify the web app is working, before opening access to it

I'll explain in more detail how the script does this below.
###Provision an EC2 instance
There are a few things to be aware of when we provision the new EC2 instance. I have chosen to deploy this in the `ap-southeast-2` region simply because it is the closest to my location. If you are located closer to another region on Amazon's infrastructure, I recommend you specify that region in the `--region` argument instead.

Secondly, I have chosen to use CentOS because I am more familiar with that distribution of Linux. If you prefer using Amazon Linux, Ubuntu or another distribution of Linux, then you will need to find the corresponding Product Code for that distribution on the AWS Marketplace, and use that instead of the product code used in the script: `aw0evgkw8e5c1q413zgy5pjce`.

*deploy-1-instance.sh*
```sh
IMAGEID="$(aws --region ap-southeast-2 ec2 describe-images --owners aws-marketplace --filters Name=product-code,Values=aw0evgkw8e5c1q413zgy5pjce | grep -Po '(?<="ImageId": ")[^"]*')"
```
> Note: If you decide to use another distribution of Linux, you will need to make further changes in these script files to account for different package managers. These scripts depend on the `yum` package manager which is not found on other distributions such as Ubuntu.

In the next few lines in the script, we setup some security for the instance, namely a Security Group on AWS, and a key pair which will allow us to remotely connect to the instance in order to manage it. Once these commands are completed, you will have a security certificate which will authenticate your access to the instance.

*deploy-1-instance.sh*
```sh
GROUPID="$(aws ec2 create-security-group --group-name sinatra-app-sg --description "Security group for Sinatra App in EC2" | grep -Po '(?<="GroupId": ")[^"]*')"

IP="$(curl -s 'http://ipinfo.io' | grep -Po '(?<="ip": ")[^"]*')"

aws ec2 authorize-security-group-ingress --group-name sinatra-app-sg --protocol tcp --port 22 --cidr $IP/32

aws ec2 create-key-pair --key-name sinatra-app-key --query 'KeyMaterial' --output text > sinatra-app-key.pem

chmod 400 sinatra-app-key.pem 
```
>Note: For security reasons, the security policy setup by the script will only allow SSH access from your current IP address to manage the EC2 instance. If you are working from multiple locations, or from a location without an externally-facing static IP address, then you may want to relax this policy by omitting the line `IP="$(curl -s 'http://ipinfo.io' | grep -Po '(?<="ip": ")[^"]*')"` and replacing the `--cidr` argument `$IP/32` on the next line with `0.0.0.0/0`. This change will allow SSH access from any IP address.

Here is where we create the EC2 instance. We pass in the Image ID and Security Group ID that we obtained in the previous commands. This will deploy a `t2.micro` instance, which is eligible for Amazon's free tier. If you need to repurpose this script to deploy a different application which requires more compute resources, then you can specify a different Instance Type here.

*deploy-1-instance.sh*
```sh
INSTANCEID="$(aws ec2 run-instances --image-id $IMAGEID --security-group-ids $GROUPID --count 1 --instance-type t2.micro --key-name sinatra-app-key --query 'Instances[0].InstanceId' | tr -d '"')"

INSTANCEPUBIP="$(aws ec2 describe-instances --instance-ids $INSTANCEID --query 'Reservations[0].Instances[0].PublicIpAddress' | tr -d '"')"

sleep 60s
```
This code will also get the public IP address of the newly-created instance, so that we can connect to it via SSH. Also note that the script will wait 60 seconds before performing the next steps, while the instance starts up and initialises.

In the next few lines of code, we connect to the instance and upload the other scripts, which will be executed remotely. Those scripts handle the setup and configuration of the software required for the application.

*deploy-1-instance.sh*
```sh
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem deploy-2-rvm.sh centos@$INSTANCEPUBIP:~/
ssh -o StrictHostKeyChecking=no -i sinatra-app-key.pem centos@$INSTANCEPUBIP -t 'bash -lc ~/deploy-2-rvm.sh'
```
###RVM, Ruby, Nginx and Passenger
Once we have a new instance running, we can connect to it for the first time and start installing the software. The original script *deploy-1-instance.sh* has uploaded the next script *deploy-2-rvm.sh* and has executed it.

####Install prerequisites and update system
We start by installing some packages that are needed for RVM. This is followed by a system-wide update, to ensure there are no out-of-date dependencies, and also for good security practice.

>Note the following script is executed on the EC2 instance

*deploy-2-rvm.sh*
```sh
sudo yum install -y gcc gcc-c++ make git gpg gpg2 curl

sudo yum update -y
```
####Install RVM
In the next steps we install RVM. RVM is needed to install Ruby, which is why we are installing it first. In order to install RVM, we will import some security keys to verify that we are getting authentic packages.

*deploy-2-rvm.sh*
```sh
gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
curl -sSL https://rvm.io/mpapis.asc | sudo gpg2 --import -

curl -sSL https://get.rvm.io | sudo bash -s stable

WHOAMI=$(whoami)
sudo usermod -a -G rvm $WHOAMI

if sudo grep -q secure_path /etc/sudoers; then sudo sh -c "echo export rvmsudo_secure_path=1 >> /etc/profile.d/rvm_secure_path.sh" && echo Environment variable installed; fi
```
>Note: It is possible to install Ruby via the included package manager in CentOS, however I have chosen to install it via RVM because the available versions on RVM tend to be more recent.

In order for RVM to work, we need to logout and login again. The initial *deploy-1-instance.sh* script will take over again and execute the next steps.

*deploy-2-rvm.sh*
```sh
exit
```
Back in the *deploy-1-instance.sh* script, we upload the next script *deploy-3-nginx.sh* and remotely execute it:

*deploy-1-instance.sh*
```sh
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem deploy-3-nginx.sh centos@$INSTANCEPUBIP:~/
ssh -o StrictHostKeyChecking=no -i sinatra-app-key.pem centos@$INSTANCEPUBIP -t 'bash -lc ~/deploy-3-nginx.sh'
```
>Note: The `-o StrictHostKeyChecking=no` argument in these commands ensures we are not prompted to proceed connecting to the 'unrecognised' instance. We have already established trust since we provisioned the instance and have the correct certificates to authenticate. Without this switch we would need to manually accept the connection.

####Install Ruby, Bundler, Nginx and Passenger
In the next steps, we will install Ruby via RVM, and Bundler. This is followed by Nginx and Passenger. In order to install Passenger, we will add the Phusion Passenger software repository first, and install any prerequisites.

*deploy-3-nginx.sh*
```sh
rvm install ruby
rvm --default use ruby
gem install bundler --no-rdoc --no-ri

sudo yum install -y epel-release yum-utils
sudo yum-config-manager --enable epel

sudo yum install -y pygpgme
sudo curl --fail -sSLo /etc/yum.repos.d/passenger.repo https://oss-binaries.phusionpassenger.com/yum/definitions/el-passenger.repo

sudo yum install -y nginx passenger
```
>The simple Sinatra app we will be deploying can actually be delivered via WEBrick. However, I have chosen to host it using Nginx as the web server and Passenger as the app server, because it represents a more realistic deployment, and is also more scalable and resilient.

####Configure Passenger
In order to configure Passenger, we need to uncomment three lines in the Passenger configuration file - `sed` comes in handy for this.

*deploy-3-nginx.sh*
```sh
sudo sed -i "s/"#passenger_root"/"passenger_root"/g" /etc/nginx/conf.d/passenger.conf
sudo sed -i "s/"#passenger_ruby"/"passenger_ruby"/g" /etc/nginx/conf.d/passenger.conf
sudo sed -i "s/"#passenger_instance_registry_dir"/"passenger_instance_registry_dir"/g" /etc/nginx/conf.d/passenger.conf
```
>Here we could probably achieve the same with just one line of code: `sudo sed -i "s/"#passenger_"/"passenger_"/g" /etc/nginx/conf.d/passenger.conf`, however I have chosen to be more explicit in case other similar lines appear in the configuration file.

For security best practice, we will create a new user account used for running the app. We will call the account `sinatraapp`.

*deploy-3-nginx.sh*
```sh
sudo useradd sinatraapp
sudo mkdir -p ~sinatraapp/.ssh
touch $HOME/.ssh/authorized_keys
sudo sh -c "cat $HOME/.ssh/authorized_keys >> ~sinatraapp/.ssh/authorized_keys"
sudo chown -R sinatraapp: ~sinatraapp/.ssh
sudo chmod 700 ~sinatraapp/.ssh
sudo sh -c "chmod 600 ~sinatraapp/.ssh/*"
```
We'll also create a folder for the app to reside in, and change the ownership over to our new account.

*deploy-3-nginx.sh*
```sh
sudo mkdir -p /var/www/sinatraapp
sudo chown sinatraapp: /var/www/sinatraapp
```
###Deploying the app
Once the configuration of Passenger is completed, control will be passed back to the initial *deploy-1-instance.sh* script. From there, it will upload the next script to the instance, and it will remotely execute the script as the newly created app user account. This is important because certain configuration settings must be made under that account.

*deploy-1-instance.sh*
```sh
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem deploy-4-app.sh sinatraapp@$INSTANCEPUBIP:~/
ssh -o StrictHostKeyChecking=no -i sinatra-app-key.pem sinatraapp@$INSTANCEPUBIP -t 'bash -lc ~/deploy-4-app.sh'
```
Logged in as the new user, the following commands are executed. This is necessary in order to configure the software environment for Ruby and Bundle properly. For more information about this, see the [bundle manual](http://bundler.io/v1.11/man/bundle-install.1.html "http://bundler.io/v1.11/man/bundle-install.1.html").

Here we also clone the [simple sinatra app](https://github.com/tnh/simple-sinatra-app "https://github.com/tnh/simple-sinatra-app") from GitHub into our app folder. We then use `bundle` to install the app, and to download any necessary dependencies. The `--path vendor/bundle` argument ensures any dependencies are installed within a sub-folder so that extra permissions aren't needed to access them if they are installed globally.

*deploy-4-app.sh*
```sh
rvm --default use ruby
cd /var/www/sinatraapp
git clone git://github.com/tnh/simple-sinatra-app.git .
mkdir -p /var/www/sinatraapp/public

bundle install --path vendor/bundle
```
###Configure the app
Once the *deploy-4-app.sh* script has finished executing, control returns back to the initial script, *deploy-1-instance.sh*. From there, the final script is uploaded and remotely executed on the instance:

*deploy-1-instance.sh*
```sh
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem deploy-5-finalise.sh centos@$INSTANCEPUBIP:~/
ssh -o StrictHostKeyChecking=no -i sinatra-app-key.pem centos@$INSTANCEPUBIP -t 'bash -lc ~/deploy-5-finalise.sh'
```
The first step in configuring the app is to get the path to Ruby, so that Passenger is able to use it. We need this from the app account we created earlier. 

*deploy-5-finalise.sh*
```sh
PATHTORUBY="$(sudo -u sinatraapp -i passenger-config about ruby-command | grep -Po '(?<=Nginx : passenger_ruby ).*')"
```
We then take the path, and insert it into the configuration file located in `/etc/nginx/conf.d/`. But first, we will create the configuration file with the following code.

*deploy-5-finalise.sh*
```sh
sudo touch /etc/nginx/conf.d/sinatraapp.conf
echo "server {" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf 
echo "  listen 80;" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf 
echo "  server_name localhost;" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf 
echo "  root /var/www/sinatraapp/public;" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf
echo "  passenger_enabled on;" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf
echo "  passenger_ruby "$PATHTORUBY";" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf 
echo "}" | sudo tee --append /etc/nginx/conf.d/sinatraapp.conf
```
>Note that we are hosting the app internally on `localhost`. We are doing this until everything is tested and working, before making it available to the world.

###Testing and verifying
In order for the configuration changes above to take effect, we need to restart the web server, Nginx. After that, we will test the web app using `curl`.

*deploy-5-finalise.sh*
```sh
sudo service nginx restart

curl localhost
```
Here we run into a problem. A code 500 Internal Server error is returned because SElinux is denying access by default. So we'll bring up the log, and in particular, the item for the restriction using `cat` and `grep`, and pipe this to `audit2allow` to generate a custom module, which we will import to allow access.

*deploy-5-finalise.sh*
```sh
cd ~
sudo cat /var/log/audit/audit.log | grep nginx | grep denied | audit2allow -M mynginx

sudo semodule -i mynginx.pp
```

The changes should take effect immediately, so a webserver restart shouldn't be necessary. We then test it out by requesting the website with `curl` again, and pipe the output into *status.txt*. 

Since the app is supposed to return the text "Hellow World!", we can check the contents of *status.txt* to verify whether it matches what we expect to see. If the file contains the string "Hello World!", then we can verify that it is working.

*deploy-5-finalise.sh*
```sh
curl localhost > status.txt
WEBSTATUS="$(cat status.txt)"
IP="$(curl -s 'http://ipinfo.io' | grep -Po '(?<="ip": ")[^"]*')"

if [ "$WEBSTATUS" == "Hello World!" ]; then
	echo "Successfully deployed on localhost"
	sudo sed -i "s/"'server_name localhost'"/"'server_name '$IP"/g" /etc/nginx/conf.d/sinatraapp.conf
	sudo service nginx restart
else
	echo "Failed to deploy on localhost"
fi
```
Once we have verified that the web app is working, we reconfigure Nginx to serve the web app externally by changing `localhost` in the configuration file with the IP address of the instance. The web server is restarted once again to apply the new settings.

####Opening access to the web app
Control is now returned back to the original script, *deploy-1-instance.sh*, where we will run a final verification before opening up the web app to the internet.

To do this, we download the *status.txt* file from the instance, and ensure that it contains the output "Hello World!" as expected. If this is the case, we add a new policy to the Security Group in AWS to allow incoming HTTP traffic to the instance.

For security reasons, HTTP traffic won't be allowed to the instance until the web app is properly configured and serving the correct content.

*deploy-1-instance.sh*
```sh
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem centos@$INSTANCEPUBIP:~/status.txt ./

WEBSTATUS="$(cat status.txt)"

if [ "$WEBSTATUS" == "Hello World!" ]; then
	# Once successfully verified, open the AWS security group to allow HTTP traffic to the server
	aws ec2 authorize-security-group-ingress --group-name sinatra-app-sg --protocol tcp --port 80 --cidr 0.0.0.0/0
	echo "Success. Check http://"$INSTANCEPUBIP
else
	echo "Failed to verify deployment"
fi
```
If all goes according to plan, you should see the following message, where x.x.x.x is the IP address of your instance:

```
Success. Check http://x.x.x.x
```
##Why use this when there are tools like Chef?
Good question. My next task is to try doing this in Chef, and maybe Ansible to see how much easier it is. The main advantage here over Chef is that we don't need an agent on the instance. I'm sure there are many more advantages with Chef that overshadow this however. This was intended more as a proof-of-concept to myself, to see what was possible.

##License
These scripts are covered by the MIT License, which is reproduced below. This information is also found in the LICENSE file within the git repository.

In short, you are free to use this code in any way you see fit, including making changes to it to suit your needs. This is under the condition that I am not held liable. There is also a condition that attribution be made, but to be honest, I don't care if you don't. If you would still like to, feel free to include a comment in your code referencing the GitHub project page: https://github.com/chunna/simple-deployment

---

The MIT License (MIT)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.