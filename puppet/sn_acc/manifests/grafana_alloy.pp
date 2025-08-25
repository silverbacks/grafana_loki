# Grafana Alloy Configuration Class
# Manages Grafana Alloy configuration based on server personality

class sn_acc::grafana_alloy (
  Array[String] $personalities = [],
  String $log_level = 'info',
  Boolean $tail_from_end = true,
  String $timezone_location = 'Local',
  Boolean $enable_cost_optimization = true,
) {

  # Define base log sources that all servers should have
  $base_log_sources = [
    {
      'path' => '/var/log/messages',
      'job'  => 'system-logs',
      'type' => 'system',
    },
  ]

  # Define personality-specific log sources
  $personality_log_sources = case $personalities {
    default: { [] }
  }

  # Add Puppet Enterprise server logs if personality includes puppet_server
  $puppet_server_logs = $personalities ? {
    /puppet_server/ => [
      {
        'path'    => '/var/log/puppetlabs/puppetserver/puppetserver.log',
        'job'     => 'puppet-logs',
        'type'    => 'application',
        'service' => 'puppetserver',
      },
      {
        'path'    => '/var/log/puppetlabs/puppetdb/puppetdb.log',
        'job'     => 'puppet-logs',
        'type'    => 'application',
        'service' => 'puppetdb',
      },
      {
        'path'    => '/var/log/puppetlabs/console-services/console-services.log',
        'job'     => 'puppet-logs',
        'type'    => 'application',
        'service' => 'console-services',
      },
    ],
    default => [],
  }

  # Add LDAP server logs if personality includes ldap_server
  $ldap_server_logs = $personalities ? {
    /ldap_server/ => [
      {
        'path'    => '/var/log/ldap.log',
        'job'     => 'ldap-logs',
        'type'    => 'application',
        'service' => 'ldap',
      },
      {
        'path'    => '/var/log/slapd.log',
        'job'     => 'ldap-logs',
        'type'    => 'application',
        'service' => 'slapd',
      },
    ],
    default => [],
  }

  # Combine all log sources
  $all_log_sources = $base_log_sources + $puppet_server_logs + $ldap_server_logs

  # Configuration hash for the template
  $alloy_config = {
    'log_level'                => $log_level,
    'personalities'            => $personalities,
    'log_sources'              => $all_log_sources,
    'tail_from_end'            => $tail_from_end,
    'timezone_location'        => $timezone_location,
    'enable_cost_optimization' => $enable_cost_optimization,
  }

  # Generate the Alloy configuration file
  file { '/etc/alloy/config.alloy':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('sn_acc/grafana_config.alloy.epp', { 'config' => $alloy_config }),
    notify  => Service['alloy'],
  }

  # Ensure Alloy service is running and enabled
  service { 'alloy':
    ensure => running,
    enable => true,
  }
}

# Usage examples for different server types:

# Example 1: Basic RHEL server (only /var/log/messages)
class { 'sn_acc::grafana_alloy':
  personalities => [],
}

# Example 2: Puppet Enterprise server
class { 'sn_acc::grafana_alloy':
  personalities => ['puppet_server'],
  log_level     => 'debug',  # More verbose for Puppet servers
}

# Example 3: LDAP server
class { 'sn_acc::grafana_alloy':
  personalities => ['ldap_server'],
}

# Example 4: Multi-role server (Puppet + LDAP)
class { 'sn_acc::grafana_alloy':
  personalities => ['puppet_server', 'ldap_server'],
}

# Example 5: Custom log sources (can be extended)
class sn_acc::grafana_alloy::custom (
  Array[Hash] $additional_log_sources = [],
) inherits sn_acc::grafana_alloy {
  
  # Override the configuration to include additional log sources
  $extended_config = $alloy_config + {
    'log_sources' => $alloy_config['log_sources'] + $additional_log_sources,
  }

  File['/etc/alloy/config.alloy'] {
    content => epp('sn_acc/grafana_config.alloy.epp', { 'config' => $extended_config }),
  }
}