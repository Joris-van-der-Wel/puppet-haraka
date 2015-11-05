class haraka::plugin::relay_acl (
  $acl_allow = [],
) {

  if ( !member($haraka::plugins, 'relay_acl') ) {
    warning('"relay_acl" plugin is not configured to load')
  }

  file { '/etc/haraka/config/relay_acl_allow':
    require => Class['haraka::initialize_config'],
    ensure => 'file',
    owner => 'haraka-src',
    group => 'haraka',
    content => inline_template('<%= @acl_allow.join("\n") + "\n" %>'),
  }
}
