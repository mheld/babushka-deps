pkg 'coreutils', :for => :osx do
  provides 'gecho'
  after :on => :osx do
    in_dir pkg_manager.bin_path do
      sudo "ln -s gecho echo"
    end
  end
end
pkg 'curl' do
  installs {
    via :apt, 'curl'
  }
end
pkg 'gettext', :for => :linux
pkg 'erlang'
pkg 'emacs'
pkg 'freeimage' do
  installs {
    via :apt, %w[libfreeimage3 libfreeimage-dev]
    via :macports, 'freeimage'
  }
  provides []
end
pkg 'gettext'
pkg 'htop'
gem 'image_science' do
  requires 'freeimage'
  provides []
end
pkg 'java' do
  installs { via :apt, 'sun-java6-jre' }
  provides 'java'
  after { shell "set -Ux JAVA_HOME /usr/lib/jvm/java-6-sun" }
end
pkg 'jnettop' do
  installs { via :apt, 'jnettop' }
end
pkg 'libssl headers' do
  installs { via :apt, 'libssl-dev' }
  provides []
end
pkg 'libxml' do
  installs { via :apt, 'libxml2-dev' }
  provides []
end
pkg 'mdns' do
  installs {
    via :apt, 'avahi-daemon'
  }
  provides []
end
pkg 'memcached'
pkg 'ncurses' do
  installs {
    via :apt, 'libncurses5-dev', 'libncursesw5-dev'
    via :macports, 'ncurses', 'ncursesw'
  }
  provides []
end
pkg 'nmap'
pkg 'oniguruma'
gem 'passenger' do
  installs 'passenger' => '>= 2.2.9'
  provides 'passenger-install-nginx-module'
end
pkg 'pcre' do
  installs {
    via :brew, 'pcre'
    via :apt, 'libpcre3-dev'
  }
  provides 'pcretest'
end
pkg 'rcconf' do
  installs { via :apt, 'rcconf' }
end
pkg 'screen'
pkg 'sed' do
  installs { via :macports, 'gsed' }
  provides 'sed'
  after {
    in_dir '/opt/local/bin' do
      sudo "ln -s gsed sed"
    end
  }
end
pkg 'sshd' do
  installs {
    via :apt, 'openssh-server'
  }
end
pkg 'vim'
pkg 'wget'
pkg 'zlib headers' do
  installs { via :apt, 'zlib1g-dev' }
  provides []
end
pkg 'zsh'