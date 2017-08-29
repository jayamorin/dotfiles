# dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Personal collection of configuration files.

## Jenkins (Ubuntu 17.04)

1. Install Oracle Java JRE and JDK
```
sudo add-apt-repository ppa:webupd8team/java
sudo apt-get update
sudo apt-get install java-common oracle-java8-installer
```

2. Copy configuration file [etc/systemd/system/jenkins.service](https://github.com/jayamorin/dotfiles/blob/master/etc/systemd/system/jenkins.service) to /etc/systemd/system/jenkins.service.

3. Download [jenkins.war](http://mirrors.jenkins.io/war/latest/jenkins.war) file and copy to /opt/jenkins.
```
$ mkdir /opt/jenkins
$ curl -L http://mirrors.jenkins.io/war/latest/jenkins.war -o /opt/jenkins/jenkins.war
```

4. Reload service manager
```
sudo systemctl daemon-reload
```

5. Manage the service with:
```
sudo systemctl start jenkins
sudo systemctl stop jenkins
sudo systemctl restart jenkins
sudo systemctl enable jenkins
```


## Vim (Ubuntu 17.04)

1. Create directories
```
mkdir -p ~/.vim/backups
```

2. Install Vim plugins

    pathogen
    ```
    mkdir -p ~/.vim/autoload ~/.vim/bundle
    curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
    ```

    NERD_tree
    ```
    cd ~/.vim/bundle
    git clone https://github.com/scrooloose/nerdtree.git
    ```

    airline
    ```
    cd ~/.vim/bundle
    git clone https://github.com/bling/vim-airline ~/.vim/bundle/vim-airline
    ```

    minibufexpl
    ```
    cd ~/.vim/bundle
    git clone https://github.com/fholgado/minibufexpl.vim
    ```

    python-mode
    ```
    cd ~/.vim/bundle
    git clone https://github.com/klen/python-mode
    ```

    vim-colorschemes
    ```
    git clone https://github.com/flazz/vim-colorschemes.git /tmp/vim-colorschemes
    mv /tmp/vim-colorschemes/colors ~/.vim/
    ```

    nerdtree-git-plugin
    ```
    cd ~/.vim/bundle
    git clone https://github.com/Xuyuanp/nerdtree-git-plugin.git ~/.vim/bundle/nerdtree-git-plugin
    ```

    vim-tmux-navigator
    ```    
    cd ~/.vim/bundle
    git clone https://github.com/christoomey/vim-tmux-navigator
    ```

    bash-support
    ```
    cd ~/.vim/bundle
    git clone https://github.com/WolfgangMehner/bash-support.git
    ```

3. Install Vim
```
sudo apt-get remove vim-tiny
sudo apt-get install vim vim-gui-common
```

4. Copy configuration file [home/.vim/vimrc](https://github.com/jayamorin/dotfiles/blob/master/home/.vim/vimrc) to ~/.vim/vimrc.


## tmux (Ubuntu 17.04)

1. Install tmux
```
sudo apt-get install tmux
```

2. Install tmux-gitbar:
```
git clone https://github.com/aurelien-rainone/tmux-gitbar.git ~/.tmux-gitbar
```

3. Copy configuration file [home/.tmux.conf](https://github.com/jayamorin/dotfiles/blob/master/home/.tmux.conf) to ~/.tmux.conf.


## Git

1. Copy configuration file [home/.gitconfig](https://github.com/jayamorin/dotfiles/blob/master/home/.gitconfig) to ~/.gitconfig and update the following with your own entry.
    ```
    [user]
        name = Jay Amorin
        email = 17937853+jayamorin@users.noreply.github.com
    ```


## Noteworthy dotfiles

Noteworthy dotfiles [here](https://dotfiles.github.io/).
