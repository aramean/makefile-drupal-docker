ENV_LOCAL=.env.local
ENV_DOCKER=.env

include $(ENV_LOCAL)
include $(ENV_DOCKER)

SHELL := /bin/bash # Use bash syntax
ENV_LOCAL_ALL=$(shell cat $(ENV_LOCAL) | while read -r line ; do echo "-e $$line"; done)
LOCAL_APPSERVER_PORT=$(shell (source $(ENV_LOCAL) && echo $$SERVER_PORT))
LOCAL_DBSERVER_PORT=$(shell (source $(ENV_LOCAL) && echo $$DB_PORT))
CURRENT_RUNNER=$(shell (ls /.dockerenv >> /dev/null 2>&1 && echo PHPDocker) || echo PHP)
CURRENT_DBSERVER=$(shell (nc -dvzw1 localhost $(LOCAL_DBSERVER_PORT) &> /dev/null && echo true || echo false))
CURRENT_IS_DBSERVER_DOCKER=$(shell docker ps -q -f name=$(DOCKER_DB_CONTAINER_NAME) 2> /dev/null | grep -q '^' && echo true || echo false)
CURRENT_IS_APPSERVER_DOCKER=$(shell docker ps -q -f name=$(DOCKER_APP_CONTAINER_NAME) 2> /dev/null | grep -q '^' && echo true || echo false)
CURRENT_IS_APPSERVER_LOCAL=$(shell (nc -dvzw1 localhost $(LOCAL_APPSERVER_PORT) &> /dev/null && echo true || echo false))
CURRENT_DATE=$(shell date +%F_%T)
DB_REMOTE_SERVER_DUMP_FILE=$(DB_REMOTE_SERVER_DBNAME)_$(CURRENT_DATE).sql

default: install build

install: composer%install

update: composer%update

clear: drupal%clear

domains: drupal%config-domains

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

drupal%clear:
	@if [ $(CURRENT_IS_APPSERVER_LOCAL) = true ] ; then \
		cd $(APP_DRUPAL_DIR) ; \
		echo -en "\033[3;33mCLI: \033[0m" ; \
		drush cache-clear all ; \
	fi;
	@if [ $(CURRENT_IS_APPSERVER_DOCKER) = true ] ; then \
		echo -en "\033[3;33mDocker: \033[0m" ; \
		docker exec -i $(DOCKER_APP_CONTAINER_NAME) drush cache-clear all ; \
	fi;

drupal%install:
	@drush dl drupal-7 --drupal-project-rename=$(APP_DRUPAL_DIR)
	@make file:sync

drupal%config-domains:
	@$(eval MODULE="$(shell composer show -- drupal/domain &> /dev/null && echo true || echo false)")
	@if [ $(MODULE) = false ] ; then \
		echo -e "\033[1;31m[ERROR] Drupal module not found or installed\033[0m"; \
		exit 1; \
	fi;
	@if [ $(CURRENT_IS_APPSERVER_LOCAL) = true ] ; then \
		cd $(APP_DRUPAL_DIR) ; \
		echo -en "\033[3;33mCLI: \033[0m\n" ; \
		echo -e "\n*------------* \033[33m DOMAINS \033[0m *------------*\n" ; \
		drush sqlq "SELECT domain_id, subdomain FROM domain ORDER BY domain_id" ; \
		echo -en "\033[1;31m\nDo you want to use localhost:$(LOCAL_APPSERVER_PORT)?\033[0m \033[1;36m[y/n]\033[0m: " ; \
		read RESPONSE ; \
		if [[ $$RESPONSE = [yY] ]] ; then \
			echo -e "\033[1;33mReconfigurating subdomains with localhost on port $(LOCAL_APPSERVER_PORT) ...\033[0m" ; \
			drush sqlq "UPDATE domain SET subdomain = 'localhost' WHERE is_default = 1; UPDATE domain SET subdomain = CONCAT(SUBSTRING_INDEX(subdomain, '.', 1), '.localhost:$(LOCAL_APPSERVER_PORT)') WHERE is_default = 0" ; \
		fi ; \
	fi;
	@if [ $(CURRENT_IS_APPSERVER_DOCKER) = true ] ; then \
		echo -en "\033[3;33mDocker: \033[0m\n" ; \
		echo -e "\n*------------* \033[33m DOMAINS \033[0m *------------*\n" ; \
		docker exec -i $(DOCKER_APP_CONTAINER_NAME) drush sqlq "SELECT domain_id, subdomain FROM domain ORDER BY domain_id" ; \
		echo -en "\033[1;31m\nDo you want to use localhost:$(SERVER_PORT)? \033[1;36m[y/n]\033[0m: " ; \
		read RESPONSE ; \
		if [[ $$RESPONSE = [yY] ]] ; then \
			echo -e "\033[1;33mReconfigurating subdomains with localhost on port $(SERVER_PORT) ...\033[0m" ; \
			docker exec -i $(DOCKER_APP_CONTAINER_NAME) drush sqlq "UPDATE domain SET subdomain = 'localhost' WHERE is_default = 1; UPDATE domain SET subdomain = CONCAT(SUBSTRING_INDEX(subdomain, '.', 1), '.localhost:$(SERVER_PORT)') WHERE is_default = 0" ; \
		fi ; \
	fi;

php%test-lint:
	@find . -type f -name '*.php' -exec php -l {} \;

php%test-unit:
	@php ./$(APP_DRUPAL_DIR)/scripts/run-tests.sh -all

php%test:
	@make php:test-lint
	@make php:test-unit

php%serve:
	@if [ $(CURRENT_RUNNER) = "PHP" ] ; then \
		if [ $(CURRENT_DBSERVER) ]; then echo -e "\033[1;33m[WARNING]\033[0m MySQL/MariaDB already running on port $(DB_PORT)."; else make db:serve; fi ; \
	fi;
	@if ! [ -a $(APP_DRUPAL_DIR) ] ; then \
		echo -e "\033[1;33m[WARNING]\033[0m Drupal not found. Creating ./$(APP_DRUPAL_DIR) ..." ; \
		make drupal:install ; \
	fi;
	@make file:sync
	@php -S localhost:$(LOCAL_APPSERVER_PORT) -t $(APP_DRUPAL_DIR) ; \

php%stop:
	@pkill -9 php &> /dev/null || true

db%serve:
	$(info Running MySQL/MariaDB on port $(DB_PORT).)
	@docker-compose run $(ENV_LOCAL_ALL) -p $(DB_PORT):$(DB_PORT) -d --rm --no-deps --name $(DOCKER_DB_CONTAINER_NAME) db

db%export:
	@echo -e "\n*------------* \033[33m EXPORT DATABASE \033[0m *------------*\n\n\033[1;33mEnvironment:\033[0m Production\n\033[1;33mDatabase:\033[0m $(DB_REMOTE_SERVER_DBNAME)\n\033[1;33mServer:\033[0m $(DB_REMOTE_SERVER_HOST)\n"
	@read -p "Where do you want save the sql dump file? Eg. /tmp: " DUMP_PATH ; \
	if ! [ -a $$DUMP_PATH ] || [ -z $$DUMP_PATH ] ; then \
		echo -e "\033[1;31m[ERROR] Path not found\033[0m"; \
	else \
		ssh $(DB_REMOTE_TUNNELSERVER) -p $(DB_REMOTE_TUNNELSERVER_SSHPORT) "mysqldump --single-transaction -h $(DB_REMOTE_SERVER_HOST) -u$(DB_REMOTE_SERVER_DBUSER) -p$(DB_REMOTE_SERVER_DBPASSWORD) $(DB_REMOTE_SERVER_DBNAME)" > $$DUMP_PATH/$(DB_REMOTE_SERVER_DUMP_FILE) ; \
		if [ -a $$DUMP_PATH/$(DB_REMOTE_SERVER_DUMP_FILE) ] ; then \
			echo -e "\033[1;36m[OK]\033[0m sql dump file saved: $$DUMP_PATH/$(DB_REMOTE_SERVER_DUMP_FILE)"; \
		else \
			echo -e "\033[1;31m[ERROR] Unable to save sql dump file\033[0m"; \
		fi; \
	fi;

db%import:
	@$(eval DB_LOCAL_HOST="$(shell source $(ENV_LOCAL) && echo $$DB_HOST)")
	@$(eval DB_LOCAL_PORT="$(shell source $(ENV_LOCAL) && echo $$DB_PORT)")
	@$(eval DB_LOCAL_DBUSER="$(shell source $(ENV_LOCAL) && echo $$DB_USERNAME)")
	@$(eval DB_LOCAL_DBPASSWORD="$(shell source $(ENV_LOCAL) && echo $$DB_PASSWORD)")
	@echo -e "\n*----------* \033[33m IMPORT DATABASE \033[0m *----------*\n\n\033[1;33mHost:\033[0m $(DB_LOCAL_HOST)\n\033[1;33mPort:\033[0m $(DB_LOCAL_PORT)\n"
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

destroy: stop
	@echo -en "\033[5;31mAre you sure you want to continue?\033[0m \033[1;36m[y/n]\033[0m: " ; \
	read RESPONSE ; \
	if [[ $$RESPONSE = [yY] ]] ; then \
		docker-compose rm -vf ; \
	fi;

file%sync:
	@rsync --recursive --compress --human-readable --update sites $(APP_DRUPAL_DIR)
	@cp $(ENV_LOCAL) $(APP_DRUPAL_DIR)/.env

doctor:
	@echo -n "Composer: " && type composer >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "Copy (cp): " && type cp >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "Docker: " && type docker >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "Grep: " && type grep >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "Rsync: " && type rsync >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "Mysql (Client): " && type mysql >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "Netcat (nc): " && type nc >/dev/null &>/dev/null && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "PHP: " && type php >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "PHPUnit: " && type phpunit >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "Pkill: " && type pkill >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "Rsync: " && type rsync >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)
	@echo -n "Source: " && type source >/dev/null 2>&1 && echo -e "\033[1;36m[OK]\033[0m" || (echo -e "\033[5;31m[Not found]\033[0m";)

make%debug:
	@echo -e "Application database generated dump name: \033[1;36m$(DB_REMOTE_SERVER_DUMP_FILE)\033[0m"
	@echo -e "Application running docker on localhost@$(DOCKER_APP_PUBLISHED_PORT): \033[1;36m[$(CURRENT_IS_APPSERVER_DOCKER)]\033[0m"
	@echo -e "Application listening on localhost@$(LOCAL_APPSERVER_PORT): \033[1;36m[$(CURRENT_IS_APPSERVER_LOCAL)]\033[0m"
	@echo -e "Database listening on localhost@$(DB_PORT): \033[1;36m[$(CURRENT_DBSERVER)]\033[0m"
	@echo -e "Database using Docker: \033[1;36m[$(CURRENT_IS_DBSERVER_DOCKER)]\033[0m"
	@echo -e "Current environment runner: \033[1;36m$(CURRENT_RUNNER)\033[0m"
	@echo -e "Current date: \033[1;36m$(CURRENT_DATE)\033[0m"
	@echo -e "Local environment parameters: \033[1;36m$(ENV_LOCAL_ALL)\033[0m"
