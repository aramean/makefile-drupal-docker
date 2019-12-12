ENV_LOCAL=.env.local
ENV_DOCKER=.env

include $(ENV_LOCAL)
include $(ENV_DOCKER)

SHELL := /bin/bash # Use bash syntax
ENV_LOCAL_ALL=$(shell cat $(ENV_LOCAL) | while read -r line ; do echo "-e $$line"; done)
CURRENT_RUNNER=$(shell (ls /.dockerenv >> /dev/null 2>&1 && echo PHPDocker) || echo PHP)
CURRENT_DBSERVER=$(shell (nc -dvzw1 localhost 3306 &>/dev/null && echo true || echo false))
CURRENT_IS_DBSERVER_DOCKER=$(shell docker inspect --format="{{.State.Running}}" $(DOCKER_DB_CONTAINER_NAME) 2> /dev/null)
CURRENT_DATE=$(shell date +%F_%T)

# Variables for db:download
DB_REMOTE_SERVER_HOST=yourhost.com
DB_REMOTE_SERVER_DBNAME=ENTER_YOUR_DB_NAME
DB_REMOTE_SERVER_DBUSER=root_pull
DB_REMOTE_SERVER_DBPASSWORD=ENTER_YOUR_DB_PASSWORD
DB_REMOTE_SERVER_DUMP_FILE=$(DB_REMOTE_SERVER_DBNAME)_$(CURRENT_DATE).sql
DB_REMOTE_TUNNELSERVER=root@yourserver.com
DB_REMOTE_TUNNELSERVER_SSHPORT=2244

# Variables for php:server
APP_DRUPAL_DIR=web

default: install build

install: composer%install

update: composer%update

rebuild: drupal%rebuild

start: install build up

restart: down up

stop: php%stop
	docker-compose stop

build:
	docker-compose build

up:
	docker-compose up -d

down:
	docker-compose down

logs:
	docker-compose logs -f

drupal%rebuild:
	@php sites/all/modules/contrib/registry_rebuild/registry_rebuild.php

drupal%clean:
	@drush cc clean

drupal%install:
	@drush dl drupal-7 --drupal-project-rename=$(APP_DRUPAL_DIR)
	@make file:sync

php%test-lint:
	@find . -type f -name '*.php' -exec php -l {} \;

php%test-unit:

php%test:
	@make php:test-lint
	@make php:test-unit

php%serve:
	@$(eval LOCAL_SERVER_PORT="$(shell source $(ENV_LOCAL) && echo $$SERVER_PORT)")
	@if [ $(CURRENT_RUNNER) = "PHP" ] ; then \
		if [ $(CURRENT_DBSERVER) ]; then echo "[WARNING] MySQL/MariaDB already running on port $(DB_PORT)."; else make db:serve; fi ; \
	fi;
	@if ! [ -a $(APP_DRUPAL_DIR) ] ; then \
		echo "[WARNING] Drupal not found. Creating $(APP_DRUPAL_DIR) ..." ; \
		make drupal:install ; \
	fi;
	@make file:sync
	@php -S localhost:$(LOCAL_SERVER_PORT) -t $(APP_DRUPAL_DIR) ; \

php%stop:
	@pkill -9 php &> /dev/null || true

db%serve:
	$(info Running MySQL/MariaDB on port $(DB_PORT).)
	docker-compose run $(ENV_LOCAL_ALL) -p $(DB_PORT):$(DB_PORT) -d --rm --no-deps --name $(DOCKER_DB_CONTAINER_NAME) db

db%export:
	@echo -e "\n|===============EXPORT DATABASE DUMP===============|\n\
	|  Environment: Production                	   |\n\
	|  Database: $(DB_REMOTE_SERVER_DBNAME)				   |\n\
	|  Server: $(DB_REMOTE_SERVER_HOST)                   |\n\
	|--------------------------------------------------|\n"
	@read -p "Where do you want save the sql dump file? Eg. /tmp: " DUMP_PATH ; \
	if ! [ -a $$DUMP_PATH ] || [ -z $$DUMP_PATH ] ; then \
		echo -e "\033[1;31m[ERROR] Path not found\033[0m"; \
	else \
		ssh $(DB_REMOTE_TUNNELSERVER) -p $(DB_REMOTE_TUNNELSERVER_SSHPORT) "mysqldump --single-transaction -h $(DB_REMOTE_SERVER_HOST) -u$(DB_REMOTE_SERVER_DBUSER) -p$(DB_REMOTE_SERVER_DBPASSWORD) $(DB_REMOTE_SERVER_DBNAME)" > $$DUMP_PATH/$(DB_REMOTE_SERVER_DUMP_FILE) ; \
		if [ -a $$DUMP_PATH/$(DB_REMOTE_SERVER_DUMP_FILE) ] ; then \
			echo "[OK] sql dump file saved: $$DUMP_PATH/$(DB_REMOTE_SERVER_DUMP_FILE)"; \
		else \
			echo -e "\033[1;31m[ERROR] Unable to save sql dump file\033[0m"; \
		fi; \
	fi;

db%import:
	@$(eval DB_LOCAL_HOST="$(shell source $(ENV_LOCAL) && echo $$DB_HOST)")
	@$(eval DB_LOCAL_PORT="$(shell source $(ENV_LOCAL) && echo $$DB_PORT)")
	@$(eval DB_LOCAL_DBUSER="$(shell source $(ENV_LOCAL) && echo $$DB_USERNAME)")
	@$(eval DB_LOCAL_DBPASSWORD="$(shell source $(ENV_LOCAL) && echo $$DB_PASSWORD)")
	@echo -e "\n|========IMPORT DATABASE DUMP========|\n\
	|  Host: $(DB_LOCAL_HOST)                   |\n\
	|  Port: $(DB_LOCAL_PORT)                        |\n\
	|------------------------------------|\n"
	@read -p "Enter location of sql dump file: " DUMP_PATH ; \
	if ! [ -a $$DUMP_PATH ] ; then \
		echo -e "\033[1;31m[ERROR] sql dump file not found in path\033[0m"; \
	else \
		if [ $(CURRENT_IS_DBSERVER_DOCKER) ] ; then \
			docker exec -i $(DOCKER_DB_CONTAINER_NAME) mysql -uroot -p$(DOCKER_DB_PASSWORD) $(DB_NAME) < $$DUMP_PATH ; \
		else \
			mysql -u$(DB_LOCAL_DBUSER) -p$(DB_LOCAL_DBPASSWORD) $(DB_LOCAL_HOST) < $$DUMP_PATH ; \
		fi; \
	fi;

composer%install:
	@composer install

composer%update:
	@composer update

clean: php%stop down
	docker system prune -f
	docker volume prune -f

file%sync:
	@rsync --recursive --compress --human-readable --update sites $(APP_DRUPAL_DIR)
	@cp $(ENV_LOCAL) $(APP_DRUPAL_DIR)/.env

doctor:
	@echo -n "Composer: " && type composer >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "Copy (cp): " && type cp >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "Docker: " && type docker >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "Drush: " && type drush >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "Mysql (Client): " && type mysql >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "Netcat (nc): " && type nc >/dev/null &>/dev/null && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "PHP: " && type php >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "PHPUnit: " && type phpunit >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "Pkill: " && type pkill >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "Rsync: " && type rsync >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)
	@echo -n "Sed: " && type sed >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[1;31m[Not found]\033[0m";)

make%debug:
	@echo -e "Application binary name: [false]"
	@echo -e "Application database directory: [false]"
	@echo -e "Application database generated dump file: $(APP_DB_DIR)/$(APP_DB_DUMP_FILE)"
	@echo -e "Database listening on localhost@$(DB_PORT): [$(CURRENT_DBSERVER)]"
	@echo -e "Database using Docker: [$(CURRENT_IS_DBSERVER_DOCKER)]"
	@echo -e "Current environment runner: $(CURRENT_RUNNER)"
	@echo -e "Current date: $(CURRENT_DATE)"
	@echo -e "Local environment parameters: $(ENV_LOCAL_ALL)"
