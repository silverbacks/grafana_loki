# Integration Snippet for Existing Grafana Alloy Module
# Add this to your existing Grafana Alloy Puppet module

# 1. Add personality detection to your main manifest or params.pp:

# In manifests/params.pp or init.pp
class grafana_alloy::params {
  
  # Auto-detect server personalities based on installed packages/services
  $detected_personalities = [
    # Check for Puppet Enterprise server
    $facts['pe_server_version'] ? {
      undef   => undef,
      default => 'puppet_server'
    },
    
    # Check for LDAP services
    $facts['packages']['openldap-servers'] ? {
      undef   => undef,
      default => 'ldap_server'
    },
    
    # Check for 389 Directory Server
    $facts['packages']['389-ds-base'] ? {
      undef   => undef,
      default => 'ldap_server'
    },
    
    # Add more personality detection as needed
  ].filter |$personality| { $personality != undef }

  # Default log configuration
  $default_log_sources = [
    {
      'path' => '/var/log/messages',
      'job'  => 'system-logs',
      'type' => 'system',
    }
  ]
}

# 2. Extend your main class to support personalities:

class grafana_alloy (
  # Your existing parameters
  String $loki_endpoint,
  String $loki_username,
  Sensitive[String] $loki_password,
  
  # New personality-based parameters
  Array[String] $personalities = $grafana_alloy::params::detected_personalities,
  Array[Hash] $additional_log_sources = [],
  Boolean $enable_personality_logs = true,
  
) inherits grafana_alloy::params {

  # Your existing Alloy installation code here...

  # Add personality-based log configuration
  if $enable_personality_logs {
    include grafana_alloy::personality_config
  }
}

# 3. Create a new class for personality-based configuration:

class grafana_alloy::personality_config {

  # Get personalities from main class
  $personalities = $grafana_alloy::personalities

  # Define personality-specific log sources
  $puppet_server_logs = 'puppet_server' in $personalities ? {
    true => [
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
    ],
    false => [],
  }

  $ldap_server_logs = 'ldap_server' in $personalities ? {
    true => [
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
    false => [],
  }

  # Combine all log sources
  $all_log_sources = $grafana_alloy::params::default_log_sources + 
                     $puppet_server_logs + 
                     $ldap_server_logs + 
                     $grafana_alloy::additional_log_sources

  # Configuration for template
  $config = {
    'log_level'                => $grafana_alloy::log_level,
    'personalities'            => $personalities,
    'log_sources'              => $all_log_sources,
    'tail_from_end'            => true,
    'positions_file'           => '/var/lib/alloy/positions.yaml',
    'timezone_location'        => 'Local',
    'enable_cost_optimization' => true,
  }

  # Update Alloy configuration
  file { '/etc/alloy/config.alloy':
    ensure  => file,
    owner   => 'root',
    group   => 'root', 
    mode    => '0644',
    content => epp('grafana_alloy/config.alloy.epp', { 'config' => $config }),
    notify  => Service['alloy'],
  }
}

# 4. Usage examples in site.pp or node definitions:

# Basic server - auto-detects personalities
node 'web-server-01' {
  class { 'grafana_alloy':
    loki_endpoint => 'https://logs-prod-us-central1.grafana.net/loki/api/v1/push',
    loki_username => '123456',
    loki_password => Sensitive('your-api-key'),
  }
}

# Puppet Enterprise server - explicitly set personality
node 'puppet-master-01' {
  class { 'grafana_alloy':
    loki_endpoint => 'https://logs-prod-us-central1.grafana.net/loki/api/v1/push',
    loki_username => '123456',
    loki_password => Sensitive('your-api-key'),
    personalities => ['puppet_server'],
  }
}

# Multi-role server with custom logs
node 'directory-server-01' {
  class { 'grafana_alloy':
    loki_endpoint         => 'https://logs-prod-us-central1.grafana.net/loki/api/v1/push',
    loki_username         => '123456',
    loki_password         => Sensitive('your-api-key'),
    personalities         => ['ldap_server'],
    additional_log_sources => [
      {
        'path'    => '/var/log/custom-app.log',
        'job'     => 'custom-logs',
        'type'    => 'application',
        'service' => 'custom-app',
      }
    ],
  }
}

# 5. Hiera data example (data/common.yaml):

grafana_alloy::loki_endpoint: "https://logs-prod-us-central1.grafana.net/loki/api/v1/push"
grafana_alloy::loki_username: "123456"

# Per-node personality override (data/nodes/puppet-master-01.yaml):
grafana_alloy::personalities:
  - puppet_server
grafana_alloy::additional_log_sources:
  - path: "/var/log/puppetlabs/bolt-server/bolt-server.log"
    job: "puppet-logs"
    type: "application"
    service: "bolt-server"