# dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Personal collection of configuration files. 

## Jenkins

1. Copy configuration file [etc/systemd/system/jenkins.service](https://github.com/jayamorin/dotfiles/blob/master/etc/systemd/system/jenkins.service) to /etc/systemd/system/jenkins.service.

2. Download [jenkins.war](http://mirrors.jenkins.io/war/latest/jenkins.war) file and copy to /opt/jenkins.
```
$ mkdir /opt/jenkins
$ curl -L http://mirrors.jenkins.io/war/latest/jenkins.war -o /opt/jenkins/jenkins.war
```

3. Reload service manager
```
sudo systemctl daemon-reload
```

4. Manage the service with:
```
sudo systemctl start jenkins
sudo systemctl stop jenkins
sudo systemctl restart jenkins
sudo systemctl enable jenkins
```


## Noteworthy dotfiles

Noteworthy dotfiles [here](https://dotfiles.github.io/).
