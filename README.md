# smpita/dump-db

A docker friendly mysqldump wrapper script with automatic rotation and pruning.

## Description

This script will dump and autorotate the contents of multiple databases in a configurable and friendly manner. Designed with Docker in mind, each option can be set from the CLI, environment variable, or read in from a file for use with Docker secrets. e.g. Setting `BACKUP_PASSWORD_FILE=/var/run/secrets/password` will place the contents of the file into the `BACKUP_PASSWORD` variable. For best results, use with scheduling software such as vixie's cron or mcuadros/ofelia.

## Features

* CLI and environment variable configurable
* Docker secret support
* Dump intervals as fast as 1 minute
* Automatic rotation
* Automatic pruning
* Automatic compression
* Dump multiple databases based on a list or query
* Timestamp encoded archive filenames
* Localizable timestamps

## Requirements
* bash
* mysqldump
* mysqladmin
* gzip
* date
* awk
* printf
* cp
* rm

## Usage

`./dump-db.sh -h hostname -p password -d /backups`

## Configuration

| Environment variable | CLI options | Default | Note |
|:---------------------|:------------|:--------|:-----|
|`DB_HOST` | `-h`, `--host` `[hostname]` | `localhost` | mysql server hostname |
|`DB_PORT` | `-P`, `--port` `[port]` | `3306` | port used by mysql server |
|`BACKUP_USER` | `-u`, `--user` `[username]` | `root` | username credential for connecting to the database |
|`BACKUP_PASSWORD` | `-p`, `--password` `[password]` | `password` | password credential for connecting to the database |
|`BACKUP_PATH` | `-d`, `--directory` `[/path]` | `/backups` | directory to store database dump files |
|`BACKUP_TZ` | `-t`, `--timezone` `[timezone]` | `UTC` | `/bin/date` friendly timezone to use for backup filenames and log output |
|`BACKUP_DATABASES` | `-D`, `--databases` `[db1/db2]` | | databases to backup with `/` delimiter |
|`BACKUP_DB_QUERY` | `-q`, `--query` `[query]`| `SELECT DB FROM mysql.db WHERE User NOT LIKE 'mysql.%'` | query used to find your databases if a static list is not provided, requires `--init true` (default) |
|`MYSQLDUMP_OPTIONS` | `-o`, `--options` `[options]` | `--single-transaction` | command line arguments for `mysqldump` |
|`BACKUP_LOG_FILE` | `-l`, `--log` `[/path/file]` | `false` | set to a writable path to enable logging |
|`MAX_CURRENT_BACKUPS` | `-kc`, `--keep-current` `[count]` | `60` | maxmimum backups to keep in the current folder; use 0 for no pruning |
|`MAX_HOURLY_BACKUPS` | `-kh`, `--keep-hourly` `[count]` | `24` | maxmimum backups to keep in the hourly folder; use 0 for no pruning |
|`MAX_DAILY_BACKUPS` | `-kd`, `--keep-daily` `[count]` | `7` | maxmimum backups to keep in the daily folder; use 0 for no pruning |
|`MAX_WEEKLY_BACKUPS` | `-kw`, `--keep-weekly` `[count]` | `5` | maxmimum backups to keep in the weekly folder; use 0 for no pruning |
|`MAX_MONTHLY_BACKUPS` | `-km`, `--keep-monthly` `[count]` | `12` | maxmimum backups to keep in the monthly folder; use 0 for no pruning |
|`MAX_YEARLY_BACKUPS` | `-ky`, `--keep-yearly` `[count]` | `0` | maxmimum backups to keep in the yearly folder; use 0 for no pruning |
|`MAX_CONNECT_ATTEMPTS` | `-c`, `--connect` `[count]` | `5` | maximum connection attempts before giving up on a server, requires `--init true` (default) |
|`SLEEP_BETWEEN_ATTEMPTS` | `-s`, `--sleep` `[count]` | `3` | number of seconds to wait inbetween connection attempts, requires `--init true` (default) |
|`INIT_QUERY` | `-i`, `--init` `[true/false]` |  `true` | send init query to database. Required 'true' for --query and --connect options recommended 'true' for Docker installations to mitigate container init delays |
|`BACKUP_DEBUG_LOGGING` | `--debug` `[true/false]`| `false` | change value from `false` enable additional log output |
| | `--help`, `--usage` | | this help menu |

## Contributing

All code contributions must go through a pull request and approved by a core developer before being merged.
This is to ensure proper review of all the code.

Fork the project, create a feature branch, and send a pull request.

If you would like to help take a look at the [list of issues](https://github.com/smpita/dump-db/issues).

## License

This project is released under the MIT License.
Copyright © 2019 [Sean Pearce](https://github.com/smpita).
Please see [License File](https://github.com/smpita/dump-db/blob/master/LICENSE) for more information.
