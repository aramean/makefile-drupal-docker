# Powerful Makefile for Drupal

Testet with: 
* [x] Drupal 7.x
* [ ] Drupal 8.x
* [ ] Drupal 9.x

## Available commands

#### ⬇ Docker

##### Run

Start docker containers:
```bash
$ make start
```

##### Stop

Stop all containers:
```bash
$ make stop
```

##### Destroy

Remove all containers:
```bash
$ make destroy
```

<br>

#### ⬇ CLI Web Server

##### Run
Start application:
```bash
$ make php:serve
```

<br>

#### ⬇ Database

##### Export
Export database sql-dump from available environments:
```bash
$ make db:export
```
> Your `public key` must be included in **~/.ssh/authorized_keys** (Production) for this to work!

##### Import
Import database sql dump file to your local development environment:
```bash
$ make db:import
```

##### Run

Start database with docker container:
```bash
$ make db:serve
```

<br>

#### ⬇ Testing

##### PHP

Run all tests:
```bash
$ make php:test
```
Run only lint tests:
```bash
$ make php:test-lint
```
Run only unit tests:
```bash
$ make php:test-unit
```

<br>

#### ⬇ Dependency Management

##### Update
Update dependencies:
```bash
$ make composer:update
```
##### Install
Install dependencies:
```bash
$ make composer:install
```

<br>

#### ⬇ Troubleshooting

##### Makefile
Debug Makefile variables:
```bash
$ make make:debug
```
##### Doctor
Check for missing software:
```bash
$ make doctor
```
##### Logs
Show or attach to server logs:
```bash
$ make logs
```
##### Cache
Delete the cache content in Drupal:
```bash
$ make drupal:clear
```

<br>

#### ⬇ Installation and Configuration

##### Domains <a name="ic-domains"></a>
Reconfigurate Domains in Drupal:
```bash
$ make drupal:config-domains
```
##### Drupal
Download and reinstall Drupal in CLI mode:
```bash
$ make drupal:install
```
##### Synchronize
Syncronize files in CLI mode:
```bash
$ make file:sync
```
