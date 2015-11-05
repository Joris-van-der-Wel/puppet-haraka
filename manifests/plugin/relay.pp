class haraka::plugin::relay (
  $acl_allow = undef,
) {

  if ( !member($haraka::plugins, 'relay') ) {
    warning('"relay" plugin is not configured to load')
  }

  ini_setting { 'haraka/relay.ini/acl':
    ensure => 'present',
    path => '/etc/haraka/config/relay.ini',
    section => 'relay',
    setting => 'acl',
    value => $acl_allow ? {
      undef => 'false',
      default => 'true',
    },
  }
  ~> Service['haraka']

  file { '/etc/haraka/config/relay_acl_allow':
    require => Class['haraka::initialize_config'],
    ensure => $acl_allow ? {
      undef => 'absent',
      default => 'file',
    },
    owner => 'haraka-src',
    group => 'haraka',
    content => inline_template('<%= @acl_allow.join("\n") + "\n" %>'),
  }
}
