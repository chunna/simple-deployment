#!/bin/bash -x

# Let's install some base packages that we will need to install the rest of the software
sudo yum install -y gcc gcc-c++ make git gpg gpg2 curl

# We'll also update the system to make sure there are no out-of-date dependencies, but also for security reasons
sudo yum update -y

# Let's import some GPG keys to install RVM. We really only need one, but when I tried the first one initially, it seemed to be invalid. So we'll import both for good measure
gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
curl -sSL https://rvm.io/mpapis.asc | sudo gpg2 --import -

# Let's install RVM. I've chosen this method to install Ruby, instead of through the package manager because the available versions on RVM tend to be more recent
curl -sSL https://get.rvm.io | sudo bash -s stable

# We'll also add the current user to the rvm group so we can perform RVM tasks like installing Ruby
WHOAMI=$(whoami)
sudo usermod -a -G rvm $WHOAMI

# Here we need to check whether the secure_path environment variable is set
if sudo grep -q secure_path /etc/sudoers; then sudo sh -c "echo export rvmsudo_secure_path=1 >> /etc/profile.d/rvm_secure_path.sh" && echo Environment variable installed; fi

# In order for RVM to work, we need to logout and login again. The initial deploy-1-instance.sh script will take over again and execute the next steps
exit
