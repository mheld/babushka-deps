meta :nginx do
  accepts_list_for :source
  accepts_list_for :extra_source
  template {
    helper(:nginx_bin) { var(:nginx_prefix) / 'sbin/nginx' }
    helper(:nginx_conf) { var(:nginx_prefix) / 'conf/nginx.conf' }
    helper(:nginx_cert_path) { var(:nginx_prefix) / 'conf/certs' }
    helper(:nginx_conf_for) {|domain,ext| var(:nginx_prefix) / "conf/vhosts/#{domain}.#{ext}" }
    helper(:nginx_conf_link_for) {|domain| var(:nginx_prefix) / "conf/vhosts/on/#{domain}.conf" }

    helper(:passenger_root) { Babushka::GemHelper.gem_path_for('passenger') }

    helper :nginx_running? do
      shell "netstat -an | grep -E '^tcp.*[.:]80 +.*LISTEN'"
    end

    helper :restart_nginx do
      if nginx_running?
        log_shell "Restarting nginx", "#{nginx_bin} -s reload", :sudo => true
      end
    end
  }
end

nginx 'vhost enabled' do
  requires 'vhost configured'
  met? { nginx_conf_link_for(var(:domain)).exists? }
  meet { sudo "ln -sf '#{nginx_conf_for(var(:domain), 'conf')}' '#{nginx_conf_link_for(var(:domain))}'" }
  after { restart_nginx }
end

nginx 'vhost configured' do
  define_var :www_aliases, :default => L{
    "#{var :domain} #{var :extra_domains}".split(' ').compact.map(&:strip).reject {|d|
      d.starts_with? '*.'
    }.reject {|d|
      d.starts_with? 'www.'
    }.map {|d|
      "www.#{d}"
    }.join(' ')
  }
  requires 'webserver configured'
  define_var :vhost_type, :default => 'passenger', :choices => %w[passenger proxy static]
  define_var :document_root, :default => L{ '/srv/http' / var(:domain) }
  met? { nginx_conf_for(var(:domain), 'conf').exists? }
  meet {
    render_erb "nginx/#{var :vhost_type}_vhost.conf.erb",   :to => nginx_conf_for(var(:domain), 'conf'), :sudo => true
    render_erb "nginx/#{var :vhost_type}_vhost.common.erb", :to => nginx_conf_for(var(:domain), 'common'), :sudo => true, :optional => true
  }
  after { restart_nginx if nginx_conf_link_for(var(:domain)).exists? }
end

nginx 'self signed cert' do
  requires 'webserver installed'
  met? { %w[key csr crt].all? {|ext| (nginx_cert_path / "#{var :domain}.#{ext}").exists? } }
  meet {
    in_dir nginx_cert_path, :create => "700", :sudo => true do
      log_shell("generating private key", "openssl genrsa -out #{var :domain}.key 1024", :sudo => true) and
      log_shell("generating certificate", "openssl req -new -key #{var :domain}.key -out #{var :domain}.csr",
        :sudo => true, :input => [
          var(:country, :default => 'AU'),
          var(:state),
          var(:city, :default => ''),
          var(:organisation),
          var(:organisational_unit, :default => ''),
          var(:domain),
          var(:email),
          '', # password
          '', # optional company name
          '' # done
        ].join("\n")
      ) and
      log_shell("signing certificate with key", "openssl x509 -req -days 365 -in #{var :domain}.csr -signkey #{var :domain}.key -out #{var :domain}.crt", :sudo => true)
    end
  }
end

nginx 'webserver running' do
  requires 'webserver configured', 'webserver startup script'
  met? {
    returning nginx_running? do |result|
      log "There is #{result ? 'something' : 'nothing'} listening on #{result ? result.scan(/[0-9.*]+[.:]80/).first : 'port 80'}"
    end
  }
  meet :on => :linux do
    sudo '/etc/init.d/nginx start'
  end
  meet :on => :osx do
    log_error "launchctl should have already started nginx. Check /var/log/system.log for errors."
  end
end

nginx 'webserver startup script' do
  requires 'webserver installed'
  on :linux do
    requires 'rcconf'
    met? { shell("rcconf --list").val_for('nginx') == 'on' }
    meet {
      render_erb 'nginx/nginx.init.d.erb', :to => '/etc/init.d/nginx', :perms => '755', :sudo => true
      sudo 'update-rc.d nginx defaults'
    }
  end
  on :osx do
    met? { !sudo('launchctl list').grep(/org\.nginx/).empty? }
    meet {
      render_erb 'nginx/nginx.launchd.erb', :to => '/Library/LaunchDaemons/org.nginx.plist', :sudo => true
      sudo 'launchctl load -w /Library/LaunchDaemons/org.nginx.plist'
    }
  end
end

nginx 'webserver configured' do
  requires 'webserver installed', 'www user and group'
  define_var :nginx_prefix, :default => '/opt/nginx'
  met? {
    if babushka_config? nginx_conf
      configured_root = nginx_conf.read.val_for('passenger_root')
      returning configured_root == passenger_root do |result|
        log_result "nginx is configured to use #{File.basename configured_root}", :result => result
      end
    end
  }
  meet {
    render_erb 'nginx/nginx.conf.erb', :to => nginx_conf, :sudo => true
  }
  after {
    sudo "mkdir -p #{var(:nginx_prefix) / 'conf/vhosts/on'}"
    restart_nginx
  }
end

dep 'passenger helper_server' do
  requires 'passenger', 'build tools'
  met? {
    (Babushka::GemHelper.gem_path_for('passenger') / 'ext/nginx/HelperServer').exists?
  }
  meet {
    in_dir Babushka::GemHelper.gem_path_for('passenger') do
      shell "rake clean nginx", :sudo => Babushka::GemHelper.should_sudo?
    end
  }
end

src 'webserver installed' do
  requires 'passenger helper_server', 'pcre', 'libssl headers', 'zlib headers'
  merge :versions, {:nginx => '0.7.65', :nginx_upload_module => '2.0.12'}
  source "http://nginx.org/download/nginx-#{var(:versions)[:nginx]}.tar.gz"
  extra_source "http://www.grid.net.ru/nginx/download/nginx_upload_module-#{var(:versions)[:nginx_upload_module]}.tar.gz"
  configure_args "--with-pcre", "--with-http_ssl_module",
    L{ "--add-module='#{Babushka::GemHelper.gem_path_for('passenger') / 'ext/nginx'}'" },
    "--add-module='../../nginx_upload_module-#{var(:versions)[:nginx_upload_module]}/nginx_upload_module-#{var(:versions)[:nginx_upload_module]}'"
  setup {
    prefix var(:nginx_prefix, :default => '/opt/nginx')
    provides var(:nginx_prefix) / 'sbin/nginx'
  }

  # The build process needs to write to passenger_root/ext/nginx.
  configure { log_shell "configure", default_configure_command, :sudo => Babushka::GemHelper.should_sudo? }
  build { log_shell "build", "make", :sudo => Babushka::GemHelper.should_sudo? }
  install { log_shell "install", "make install", :sudo => Babushka::GemHelper.should_sudo? }

  met? {
    if !File.executable?(var(:nginx_prefix) / 'sbin/nginx')
      unmet "nginx isn't installed"
    else
      installed_version = shell(var(:nginx_prefix) / 'sbin/nginx -V') {|shell| shell.stderr }.val_for('nginx version').sub('nginx/', '')
      if installed_version != var(:versions)[:nginx]
        unmet "an outdated version of nginx is installed (#{installed_version})"
      elsif !shell(var(:nginx_prefix) / 'sbin/nginx -V') {|shell| shell.stderr }[Babushka::GemHelper.gem_path_for('passenger').to_s]
        unmet "nginx is installed, but built against the wrong passenger version"
      else
        met "nginx-#{installed_version} is installed"
      end
    end
  }
end
