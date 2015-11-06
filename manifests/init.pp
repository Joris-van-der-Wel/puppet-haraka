class haraka (
  $version = $haraka::params::version,
  $nvm_version = $haraka::params::nvm_version,
  $node_version = $haraka::params::node_version,

  # address to listen on
  # use "[::0]:25" to listen on IPv6 and IPv4 (not all OSes)
  # Note you can listen on multiple IPs/ports using commas
  $listen = $haraka::params::listen,
  $log_file = $haraka::params::log_file,
  $pid_file = $haraka::params::pid_file,
  $spool_dir = $haraka::params::spool_dir,
  $service_ensure = $haraka::params::service_ensure,
  $service_enable = $haraka::params::service_enable,
  $plugins = $haraka::params::plugins,


  $path_export = 'export PATH=$PATH:/opt/haraka/bin/',
) inherits haraka::params {
  include haraka::user, haraka::storage, haraka::install_node, haraka::install,
          haraka::initialize_config, haraka::smtp_config, haraka::plugins_config,
          haraka::systemd_config, haraka::service
}

class haraka::params {
  $version = 'latest'
  $nvm_version = '0.29.0'
  $node_version = 'v4.2' # 4.2 is LTS

  $listen = '127.0.0.1:25'
  $log_file = '/var/log/haraka.log'
  $pid_file = '/var/run/haraka.pid'
  $spool_dir = '/var/spool/haraka'

  $service_ensure = 'running'
  $service_enable = true

  $plugins = [
    # List of plugins that Haraka will run
    #
    # Plugin ordering often matters, run 'haraka -o -c /path/to/haraka/config'
    # to see the order plugins (and their hooks) will run in.
    #
    # To see a list of all plugins, run 'haraka -l'
    #
    # To see the help docs for a particular plugin, run 'haraka -h plugin.name'

    #process_title
    # Log to syslog (see 'haraka -h log.syslog')
    # log.syslog

    # CONNECT
    #toobusy
    #relay
    # control which IPs, rDNS hostnames, HELO hostnames, MAIL FROM addresses, and
    # RCPT TO address you accept mail from. See 'haraka -h access'.
    'access',
    # connect.p0f
    # connect.geoip
    # connect.asn
    # connect.fcrdns
    # block mails from known bad hosts (see config/dnsbl.zones for the DNS zones queried)
    'dnsbl',

    # HELO
    #early_talker
    # see config/helo.checks.ini for configuration
    'helo.checks',
    # see 'haraka -h tls' for config instructions before enabling!
    # tls
    #
    # AUTH plugins require TLS before AUTH is advertised, see
    #     https://github.com/baudehlo/Haraka/wiki/Require-SSL-TLS
    # auth/flat_file
    # auth/auth_proxy
    # auth/auth_ldap

    # MAIL FROM
    # Only accept mail where the MAIL FROM domain is resolvable to an MX record
    'mail_from.is_resolvable',
    #spf

    # RCPT TO
    # At least one rcpt_to plugin is REQUIRED for inbound email. The simplest
    # plugin is in_host_list, see 'haraka -h rcpt_to.in_host_list' to configure.
    'rcpt_to.in_host_list',
    #rcpt_to.qmail_deliverable
    #rcpt_to.ldap
    #rcpt_to.routes

    # DATA
    #bounce
    # Check mail headers are valid
    'data.headers',
    #data.uribl
    #attachment
    #clamd
    #spamassassin
    #dkim_sign
    #karma

    # QUEUE
    # queues: discard  qmail-queue  quarantine  smtp_forward  smtp_proxy
    # Queue mail via smtp - see config/smtp_forward.ini for where your mail goes
    'queue/smtp_forward',

    # Disconnect client if they spew bad SMTP commands at us
    'max_unrecognized_commands',
  ]
}

class haraka::user {

  # haraka runs as this user
  @user { 'haraka':
    ensure => 'present',
    gid    => 'haraka',
    groups => [],
    system => true,
  }

  # the source & config files are owned by this user
  @user { 'haraka-src':
    ensure => 'present',
    gid    => 'haraka',
    groups => [],
    system => true,
    home => '/opt/haraka',
  }

  group { 'haraka':
    ensure => 'present',
  }
  ->
  User <| title == 'haraka-src' |>
  ->
  User <| title == 'haraka' |>
}

class haraka::storage {
  file { '/opt/haraka':
    ensure => 'directory',
    owner => 'haraka-src',
    group => 'haraka',
  }
  ->
  file { '/opt/haraka/bin':
    ensure => 'directory',
    owner => 'haraka-src',
    group => 'haraka',
  }

  file { '/etc/haraka':
    ensure => 'directory',
    owner => 'haraka-src',
    group => 'haraka',
  }
  ->
  file { '/etc/haraka/queue':
    ensure => 'directory',
    owner => 'haraka',
    group => 'haraka',
  }

  file { $haraka::spool_dir:
    ensure => 'directory',
    owner => 'haraka',
    group => 'haraka',
  }
}

class haraka::install_node {
  $cd = '/bin/cd /opt/haraka'
  $env = 'export NVM_DIR=/opt/haraka/nvm'
  $sourcenvm = 'source /opt/haraka/nvm/nvm.sh'

  ensure_packages([ # stdlib
    'wget',

    # required by node-gyp (for centos 7):
    'gcc-c++',
    'make',
    'python', # python 2
  ])

  exec { 'install nvm for haraka-src':
    command => "/bin/su -l haraka-src sh -c '$cd && $env && /bin/wget -qO- https://raw.githubusercontent.com/creationix/nvm/v${haraka::nvm_version}/install.sh | /bin/bash'",
    unless  => "/bin/test -f /opt/haraka/nvm/nvm.sh && $cd && $env && $sourcenvm && test $(nvm --version) == '${haraka::nvm_version}'"
  }
  ->
  exec { 'install node for haraka-src':
    command => "/bin/su -l haraka-src sh -c '$cd && $env && $sourcenvm && nvm install ${haraka::node_version}'",
    unless  => "/bin/su -l haraka-src sh -c '$cd && $env && $sourcenvm && nvm version ${haraka::node_version}'",
    notify => [
      Exec['link node for haraka-src'],
      Exec['link npm for haraka-src'],
    ],
  }

  exec { 'link node for haraka-src':
    command => "/bin/su -l haraka-src sh -c '$cd && $env && $sourcenvm && /bin/ln -f -s $(nvm which ${haraka::node_version}) /opt/haraka/bin/node'",
    creates => '/opt/haraka/bin/node',
  }
  ~> Service['haraka']

  exec { 'link npm for haraka-src':
    command => "/bin/su -l haraka-src sh -c '$cd && $env && $sourcenvm && /bin/ln -f -s $(/bin/dirname $(nvm which ${haraka::node_version}))/npm /opt/haraka/bin/npm'",
    creates => '/opt/haraka/bin/npm',
  }
}

class haraka::install {
  $cd = '/bin/cd /opt/haraka'
  $env = $haraka::path_export

  exec { 'install haraka using npm':
    require => [
      Class['haraka::storage'],
      Class['haraka::install_node'],
      Package['gcc-c++'],
      Package['make'],
      Package['python']
  ],
    command => "/bin/su -l haraka-src sh -c '$cd && $env && npm install Haraka@${haraka::version}'",
    unless => "/bin/su -l haraka-src sh -c '$cd && $env && npm ls Haraka@${haraka::version}'",
  }
  ->
  file { '/opt/haraka/bin/haraka':
    ensure => link,
    target => '/opt/haraka/node_modules/.bin/haraka',
    owner => 'haraka-src',
    group => 'haraka',
  }
  ~> Service['haraka']
}

class haraka::initialize_config {
  $env = $haraka::path_export

  exec { 'initialize haraka config':
    require => [ Class['haraka::install'] ],
    command => "/bin/su -l haraka-src sh -c '$env && haraka -i /etc/haraka'",
    creates => '/etc/haraka/package.json'
  }
}

class haraka::smtp_config {
  Ini_setting {
    ensure  => present,
    require => Class['haraka::initialize_config'],
    path    => '/etc/haraka/config/smtp.ini',
    notify  => Service['haraka'],
  }

  ini_setting { 'haraka/smtp.ini/user':
    setting => 'user',
    value   => 'haraka',
  }

  ini_setting { 'haraka/smtp.ini/group':
    setting => 'group',
    value   => 'haraka',
  }

  ini_setting { 'haraka/smtp.ini/daemonize':
    setting => 'daemonize',
    value   => 'true',
  }

  ini_setting { 'haraka/smtp.ini/daemon_log_file':
    setting => 'daemon_log_file',
    value   => $haraka::log_file,
  }

  ini_setting { 'haraka/smtp.ini/daemon_pid_file':
    setting => 'daemon_pid_file',
    value   => $haraka::pid_file,
  }

  ini_setting { 'haraka/smtp.ini/listen':
    setting => 'listen',
    value   => $haraka::listen,
  }
  
  ini_setting { 'haraka/smtp.ini/spool_dir':
    setting => 'spool_dir',
    value => $haraka::spool_dir,
  }
}

class haraka::plugins_config {
  $plugins = $haraka::plugins

  file { '/etc/haraka/config/plugins':
    require => Class['haraka::initialize_config'],
    ensure => 'file',
    owner => 'haraka-src',
    group => 'haraka',
    content => inline_template('<%= @plugins.join("\n") + "\n" %>'),
  } ~> Service['haraka']

}

class haraka::systemd_config {
  Ini_setting {
    ensure => present,
    path => '/usr/lib/systemd/system/haraka.service',
  }

  create_ini_settings({
    'Unit' => {
      'Description' => 'Haraka MTA',
      'After' => 'syslog.target network.target remote-fs.target nss-lookup.target',
    },

    'Service' => {
      'Type' => 'forking',
      'PIDFile' => $haraka::pid_file,
      'Environment' => 'PATH=/opt/haraka/bin',
      'ExecStart' => '/opt/haraka/bin/haraka -c /etc/haraka',
      'KillMode' => 'process',
      'PrivateTmp' => 'true',
    },

    'Install' => {
      'WantedBy' => 'multi-user.target',
    },
  })
}

class haraka::service {
  service { 'haraka':
    require => [
      Class['haraka::systemd_config']
    ],
    ensure => $haraka::service_ensure,
    enable => $haraka::service_enable
  }
}
