class tak_pgnet (
  String[1] $acme_domain,
  Boolean $acme_agree_tos = true,
  Stdlib::Absolutepath $acme_state = '/var/lib/takserver/acme',
  Stdlib::Absolutepath $data_dir = '/srv/tak-data',
  Stdlib::Absolutepath $accounts_file = '/var/lib/takserver/accounts.conf',
  Stdlib::Absolutepath $map_cache_dir = '/var/lib/takserver/maps',
  Stdlib::Absolutepath $replay_dir = '/var/lib/takserver/replays',
  Integer[1, 65535] $port = 7677,
  Integer[1, 64] $max_games = 16,
  Integer[1, 64] $max_running_games = 4,
  Integer[1] $max_accounts = 10000,
  Integer[1] $map_memory_mib = 512,
  Integer[1] $map_storage_mib = 4096,
  Integer[1] $replay_memory_mib = 256,
  Integer[1] $replay_storage_mib = 4096,
  String $extra_args = '',
  String[1] $memory_max = '8G',
  String[1] $memory_swap_max = '0',
  Integer[1] $tasks_max = 128,
  Integer[1] $limit_nofile = 1024,
  Enum['running', 'stopped'] $service_ensure = 'running',
  Boolean $service_enable = true,
  String[1] $github_repo = 'pocketgeek/tak-engine',
  Boolean $manage_data_dir = false,
) {
  if $facts['os']['name'] != 'Ubuntu' or $facts['os']['release']['major'] != '24.04' {
    fail('tak_pgnet supports Ubuntu 24.04 only')
  }

  if $max_running_games > $max_games {
    fail('tak_pgnet::max_running_games cannot be greater than tak_pgnet::max_games')
  }

  package { ['curl', 'jq', 'ca-certificates']:
    ensure => installed,
  }

  file { '/usr/local/sbin/tak-engine-install-latest':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    source  => 'puppet:///modules/tak_pgnet/tak-engine-install-latest',
    require => Package['curl', 'jq', 'ca-certificates'],
  }

  exec { 'install-latest-tak-engine-release':
    command     => "/usr/local/sbin/tak-engine-install-latest ${github_repo} ${port}",
    onlyif      => "/usr/local/sbin/tak-engine-install-latest --check ${github_repo}",
    path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    timeout     => 600,
    logoutput   => on_failure,
    require     => File['/usr/local/sbin/tak-engine-install-latest'],
  }

  if $manage_data_dir {
    file { $data_dir:
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }
  }

  file { '/etc/systemd/system/takserver.service.d':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/etc/systemd/system/takserver.service.d/acme.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('tak_pgnet/acme.conf.epp', {
      'acme_domain'            => $acme_domain,
      'acme_agree_tos'         => $acme_agree_tos,
      'acme_state'             => $acme_state,
      'data_dir'               => $data_dir,
      'accounts_file'          => $accounts_file,
      'map_cache_dir'          => $map_cache_dir,
      'replay_dir'             => $replay_dir,
      'port'                   => $port,
      'max_games'              => $max_games,
      'max_running_games'      => $max_running_games,
      'max_accounts'           => $max_accounts,
      'map_memory_mib'         => $map_memory_mib,
      'map_storage_mib'        => $map_storage_mib,
      'replay_memory_mib'      => $replay_memory_mib,
      'replay_storage_mib'     => $replay_storage_mib,
      'extra_args'             => $extra_args,
      'memory_max'             => $memory_max,
      'memory_swap_max'        => $memory_swap_max,
      'tasks_max'              => $tasks_max,
      'limit_nofile'           => $limit_nofile,
    }),
    require => File['/etc/systemd/system/takserver.service.d'],
    notify  => Exec['takserver-systemd-daemon-reload'],
  }

  exec { 'takserver-systemd-daemon-reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
  }

  service { 'takserver':
    ensure     => $service_ensure,
    enable     => $service_enable,
    hasstatus  => true,
    hasrestart => true,
    require    => [
      Exec['install-latest-tak-engine-release'],
      File['/etc/systemd/system/takserver.service.d/acme.conf'],
    ],
  }
}
