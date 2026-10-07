# tak_pgnet Puppet module

Installs the latest non-prerelease GitHub release of `pocketgeek/tak-engine` on Ubuntu 24.04, uses the `takserver.service` unit shipped by the `.deb`, writes a single Puppet-managed ACME drop-in containing all TAK server configuration overrides, and manages the service.

The node queries GitHub's `/releases/latest` endpoint during each Puppet run. It chooses the Ubuntu 24.04 `.deb` matching `dpkg --print-architecture`, verifies the GitHub-provided SHA-256 digest when present, and installs the package only when its version differs from the latest tag.

## Example

```puppet
class { 'tak_pgnet':
  acme_domain            => 'tak.example.com',
  data_dir               => '/srv/tak-data',
  port                   => 7677,
  max_games              => 16,
  max_running_games      => 4,
  max_accounts           => 10000,
  map_memory_mib         => 512,
  map_storage_mib        => 4096,
  replay_memory_mib      => 256,
  replay_storage_mib     => 4096,
  extra_args             => '',
  memory_max             => '8G',
  memory_swap_max        => '0',
  tasks_max              => 128,
  limit_nofile           => 1024,
  service_ensure         => 'running',
  service_enable         => true,
}
```

## Hiera example

```yaml
tak_pgnet::acme_domain: 'tak.example.com'
tak_pgnet::data_dir: '/srv/tak-data'
tak_pgnet::port: 7677
tak_pgnet::max_games: 16
tak_pgnet::max_running_games: 4
tak_pgnet::max_accounts: 10000
tak_pgnet::map_memory_mib: 512
tak_pgnet::map_storage_mib: 4096
tak_pgnet::replay_memory_mib: 256
tak_pgnet::replay_storage_mib: 4096
tak_pgnet::extra_args: ''
tak_pgnet::memory_max: '8G'
tak_pgnet::memory_swap_max: '0'
tak_pgnet::tasks_max: 128
tak_pgnet::limit_nofile: 1024
```

## Exposed parameters

- `acme_domain` (required)
- `acme_agree_tos` (default `true`)
- `acme_state` (default `/var/lib/takserver/acme`)
- `data_dir`
- `accounts_file`
- `map_cache_dir`
- `replay_dir`
- `port`
- `max_games`
- `max_running_games`
- `max_accounts`
- `map_memory_mib`
- `map_storage_mib`
- `replay_memory_mib`
- `replay_storage_mib`
- `extra_args`
- `memory_max`
- `memory_swap_max`
- `tasks_max`
- `limit_nofile`
- `service_ensure`
- `service_enable`
- `github_repo`
- `manage_data_dir`

The only systemd drop-in managed by the module is:

`/etc/systemd/system/takserver.service.d/acme.conf`

It contains all `TAK_SERVER_*` environment overrides, clears the packaged manual-TLS `LoadCredential` and `ExecStart`, gives `takserver` `CAP_NET_BIND_SERVICE`, applies the configured resource limits, and launches the server with `--acme-domain`, `--acme-state`, and optionally `--acme-agree-tos`.

## systemd ownership

The module intentionally does **not** manage or template the base systemd unit. The installed TAK Engine package owns:

`/usr/lib/systemd/system/takserver.service`

Puppet owns only:

`/etc/systemd/system/takserver.service.d/acme.conf`

This allows package upgrades to update the base service definition while Puppet keeps the ACME-specific configuration and service state authoritative.

## Safe upgrades while the server is in use

When a newer GitHub release is available, the installer does **not** blindly
restart a live server. Its upgrade policy is:

- If `takserver` is stopped, install the new package immediately.
- If `takserver` is running, query `takserver --status --port <configured port>`.
- If `running_games` is `0`, stop the service, install the package, reload systemd,
  and start the service again.
- If one or more games are running, defer the upgrade until a later Puppet run.
- If the status query fails or cannot be parsed, defer the upgrade rather than
  risk interrupting an active match.

The package is downloaded and SHA-256 verified before the live status check so the
actual maintenance window is kept short.

**Bootstrap note:** releases older than the server-status feature cannot prove that
a running server is idle. For those versions, a pending upgrade is safely deferred
while the service is running. Stop `takserver` once and run Puppet to install a
status-capable release; later upgrades can then occur automatically between games.

The Puppet `exec` intentionally does not notify the service resource. The installer
restarts `takserver` only when it actually performs a safe live upgrade, avoiding a
restart on every ordinary Puppet run where the installed package is already current.
