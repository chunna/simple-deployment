#!/bin/bash -x

# Get an ImageID for CentOS 7 from the AWS ap-southeast-2 region (closest to us). I found the product code via the CentOS AWS wiki (https://wiki.centos.org/Cloud/AWS)
IMAGEID="$(aws --region ap-southeast-2 ec2 describe-images --owners aws-marketplace --filters Name=product-code,Values=aw0evgkw8e5c1q413zgy5pjce | grep -Po '(?<="ImageId": ")[^"]*')"

# Create a security group for our app
GROUPID="$(aws ec2 create-security-group --group-name sinatra-app-sg --description "Security group for Sinatra App in EC2" | grep -Po '(?<="GroupId": ")[^"]*')"

# Get the IP address for our current computer, where we will be working from
IP="$(curl -s 'http://ipinfo.io' | grep -Po '(?<="ip": ")[^"]*')"

# Apply a security policy to the security group, allowing only SSH access from our current IP address
aws ec2 authorize-security-group-ingress --group-name sinatra-app-sg --protocol tcp --port 22 --cidr $IP/32

# Create a key pair used to authenticate our sessions with the EC2 instance
aws ec2 create-key-pair --key-name sinatra-app-key --query 'KeyMaterial' --output text > sinatra-app-key.pem

chmod 400 sinatra-app-key.pem 

# Create the EC2 instance
INSTANCEID="$(aws ec2 run-instances --image-id $IMAGEID --security-group-ids $GROUPID --count 1 --instance-type t2.micro --key-name sinatra-app-key --query 'Instances[0].InstanceId' | tr -d '"')"

# This returns the public facing IP address for the instance so we can connect to it
INSTANCEPUBIP="$(aws ec2 describe-instances --instance-ids $INSTANCEID --query 'Reservations[0].Instances[0].PublicIpAddress' | tr -d '"')"

# Wait a minute while the EC2 instance initialises, before we can connect to it
sleep 60s

# Here we're going to upload some scripts onto the instance, and remotely execute them to deploy the software platform
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem deploy-2-rvm.sh centos@$INSTANCEPUBIP:~/
ssh -o StrictHostKeyChecking=no -i sinatra-app-key.pem centos@$INSTANCEPUBIP -t 'bash -lc ~/deploy-2-rvm.sh'
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem deploy-3-nginx.sh centos@$INSTANCEPUBIP:~/
ssh -o StrictHostKeyChecking=no -i sinatra-app-key.pem centos@$INSTANCEPUBIP -t 'bash -lc ~/deploy-3-nginx.sh'
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem deploy-4-app.sh sinatraapp@$INSTANCEPUBIP:~/
ssh -o StrictHostKeyChecking=no -i sinatra-app-key.pem sinatraapp@$INSTANCEPUBIP -t 'bash -lc ~/deploy-4-app.sh'
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem deploy-5-finalise.sh centos@$INSTANCEPUBIP:~/
ssh -o StrictHostKeyChecking=no -i sinatra-app-key.pem centos@$INSTANCEPUBIP -t 'bash -lc ~/deploy-5-finalise.sh'

# After the scripts are run remotely, they should produce a status.txt file verifying the deployment
# Here we will download that file and verify it again before allowing public access to the web app
scp -o StrictHostKeyChecking=no -i sinatra-app-key.pem centos@$INSTANCEPUBIP:~/status.txt ./
WEBSTATUS="$(cat status.txt)"
# Verify whether the web app is serving the correct content
if [ "$WEBSTATUS" == "Hello World!" ]; then
	# Once successfully verified, open the AWS security group to allow HTTP traffic to the server
	aws ec2 authorize-security-group-ingress --group-name sinatra-app-sg --protocol tcp --port 80 --cidr 0.0.0.0/0
	echo "Success. Check http://"$INSTANCEPUBIP
else
	echo "Failed to verify deployment"
fi
