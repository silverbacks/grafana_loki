# Minimal Integration Example for Grafana Alloy Module

## 1. Add personality parameter to your main class:

```puppet
class your_alloy_module (
  # Your existing parameters...
  String $loki_endpoint,
  String $loki_username,
  
  # Add personality support
  Array[String] $personalities = [],
) {

  # Your existing code...

  # Add personality-based log sources
  $base_logs = [
    {
      'path' => '/var/log/messages',
      'job'  => 'system-logs', 
      'type' => 'system',
    }
  ]

  # Conditionally add personality-specific logs
  $puppet_logs = 'puppet_server' in $personalities ? {
    true => [
      {
        'path' => '/var/log/puppetlabs/puppetserver/puppetserver.log',
        'job'  => 'puppet-logs',
        'type' => 'application',
      }
    ],
    false => []
  }

  $ldap_logs = 'ldap_server' in $personalities ? {
    true => [
      {
        'path' => '/var/log/ldap.log', 
        'job'  => 'ldap-logs',
        'type' => 'application',
      }
    ],
    false => []
  }

  $all_log_sources = $base_logs + $puppet_logs + $ldap_logs

  # Use in your template
  file { '/etc/alloy/config.alloy':
    content => epp('your_module/config.alloy.epp', {
      'log_sources'   => $all_log_sources,
      'personalities' => $personalities,
    }),
    notify => Service['alloy'],
  }
}
```

## 2. Update your template to use the log_sources array:

```puppet
# In templates/config.alloy.epp
discovery.file "system_logs" {
  path_targets = [
<% $log_sources.each |$source| { -%>
    {
      __path__ = "<%= $source['path'] %>",
      job      = "<%= $source['job'] %>", 
      log_type = "<%= $source['type'] %>",
    },
<% } -%>
  ]
}
```

## 3. Usage examples:

```puppet
# Basic server
class { 'your_alloy_module':
  personalities => [],
}

# Puppet Enterprise server  
class { 'your_alloy_module':
  personalities => ['puppet_server'],
}

# LDAP server
class { 'your_alloy_module':
  personalities => ['ldap_server'],
}

# Multi-role server
class { 'your_alloy_module':
  personalities => ['puppet_server', 'ldap_server'],
}
```

## 4. Add personality-specific filters to template:

```puppet
<% if $personalities.any |$p| { $p == 'puppet_server' } { -%>
  // Puppet server specific error patterns
  stage.match {
    selector = "{job=\"puppet-logs\"}"
    stage.regex {
      expression = "(?i).*(puppet.*error|compilation.*failed|ca.*error).*"
    }
    stage.labels {
      values = {
        severity = "error",
        event_type = "puppet_server_error",
      }
    }
  }
<% } -%>

<% if $personalities.any |$p| { $p == 'ldap_server' } { -%>
  // LDAP server specific error patterns  
  stage.match {
    selector = "{job=\"ldap-logs\"}"
    stage.regex {
      expression = "(?i).*(authentication.*failed|ldap.*error|bind.*failed).*"
    }
    stage.labels {
      values = {
        severity = "warning", 
        event_type = "ldap_auth_failure",
      }
    }
  }
<% } -%>
```

This gives you personality-based log collection with minimal changes to your existing module!