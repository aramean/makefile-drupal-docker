include .env.local
include .env

SHELL := /bin/bash # Use bash syntax
ENV_LOCAL_ALL=$(shell cat .env.local | while read -r line ; do echo "-e $$line"; done)
CURRENT_RUNNER=$(shell (ls /.dockerenv >> /dev/null 2>&1 && echo PHPDocker) || echo PHP)
CURRENT_DBSERVER=$(shell (nc -dvzw1 localhost 3306 &>/dev/null && echo true || echo false))
CURRENT_IS_DBSERVER_DOCKER=$(shell docker inspect --format="{{.State.Running}}" $(DOCKER_DB_CONTAINER_NAME) 2> /dev/null)
CURRENT_DATE=$(shell date +%F_%T)
APP_DB_DIR=database
APP_DB_DUMP_FILE=dump.sql

# Variables for db:download
DB_REMOTE_SERVER_HOST=yourhost.com
DB_REMOTE_SERVER_DBNAME=ENTER_YOUR_DB_NAME
DB_REMOTE_SERVER_DBUSER=root_pull
DB_REMOTE_SERVER_DBPASSWORD=ENTER_YOUR_DB_PASSWORD
DB_REMOTE_SERVER_DUMP_FILE=$(DB_REMOTE_SERVER_DBNAME)_$(CURRENT_DATE).sql
DB_REMOTE_TUNNELSERVER=root@yourserver.com
DB_REMOTE_TUNNELSERVER_SSHPORT=2244

# Variables for db:import
DB_LOCAL_SERVER_ENV=.env.local

default:
        docker-compose build
up:
        docker-compose up -d

logs:
        docker-compose logs -f

down:
        docker-compose down

start: default up

restart: down up

stop: down php%kill

php%test-lint:
        @find . -type f -name '*.php' -exec php -l {} \;

php%test-unit:

php%test:
        @make php:test-lint
        @make php:test-unit

php%serve:
        @if [ $(CURRENT_RUNNER) = "PHP" ]; then \
        if $(CURRENT_DBSERVER); then echo "MySQL/MariaDB already running on port $(DB_PORT)."; else make db:serve; fi; \
        php -S localhost:$(SERVER_PORT); \
        else \
                php -S localhost:$(DOCKER_APP_PORT); \
        fi;

db%serve:
        $(info Running MySQL/MariaDB on port $(DB_PORT).)
        docker-compose run $(ENV_LOCAL_ALL) -p $(DB_PORT):$(DB_PORT) -d --rm --no-deps --name $(DOCKER_DB_CONTAINER_NAME) db

db%export:
        @echo -e "\n|===============EXPORT DATABASE DUMP===============|"
        @echo -e "|  Database: $(DB_REMOTE_SERVER_DBNAME)                      |"
        @echo -e "|  Server: $(DB_REMOTE_SERVER_HOST)                   |"
        @echo -e "|--------------------------------------------------|\n"
        @read -p "Where do you want save the sql dump? Eg. /tmp: " DUMP_PATH; \
        ssh $(DB_REMOTE_TUNNELSERVER) -p $(DB_REMOTE_TUNNELSERVER_SSHPORT) "mysqldump -h $(DB_REMOTE_SERVER_HOST) -u$(DB_REMOTE_SERVE$
        if [ -a $$DUMP_PATH/$(DB_REMOTE_SERVER_DUMP_FILE) ] ; then \
                echo "OK. Dump saved: $$DUMP_PATH/$(DB_REMOTE_SERVER_DUMP_FILE)"; \
        fi;

db%import:
        @$(eval DB_LOCAL_HOST="$(shell source $(DB_LOCAL_SERVER_ENV) && echo $$DB_HOST)")
        @$(eval DB_LOCAL_PORT="$(shell source $(DB_LOCAL_SERVER_ENV) && echo $$DB_PORT)")
        @$(eval DB_LOCAL_DBUSER="$(shell source $(DB_LOCAL_SERVER_ENV) && echo $$DB_USERNAME)")
        @$(eval DB_LOCAL_DBPASSWORD="$(shell source $(DB_LOCAL_SERVER_ENV) && echo $$DB_PASSWORD)")
        @echo -e "\n|========IMPORT DATABASE DUMP========|"
        @echo -e "|  Host: $(DB_LOCAL_HOST)                   |"
        @echo -e "|  Port: $(DB_LOCAL_PORT)                        |"
        @echo -e "|------------------------------------|\n"
        @read -p "Enter location of sql-dump: " DUMP_PATH ; \
        if ! [ -a $$DUMP_PATH ] ; then \
                echo "ERROR. Dump not found in path!"; \
        else \
                if $(CURRENT_IS_DBSERVER_DOCKER); then \
                        docker exec -i $(DOCKER_DB_CONTAINER_NAME) mysql -uroot -p$(DOCKER_DB_PASSWORD) $(DB_NAME) < $$DUMP_PATH; \
                else \
                        mysql -u$(DB_LOCAL_DBUSER) -p$(DB_LOCAL_DBPASSWORD) $(DB_LOCAL_HOST) < $$DUMP_PATH; \
                fi; \
        fi;

npm%build:
        @npm install

clean: php%kill down
        docker system prune -f
        docker volume prune -f

doctor:
        @echo -n "Docker: " && type docker >/dev/null 2>&1 && echo "[OK]" || (echo "[Not found]";)
        @echo -n "Netcat (nc): " && type nc >/dev/null &>/dev/null && echo "[OK]" || (echo "[Not found]";)
        @echo -n "PHP: " && type php >/dev/null 2>&1 && echo "[OK]" || (echo "[Not found]";)
        @echo -n "PHPUnit: " && type phpunit >/dev/null 2>&1 && echo "[OK]" || (echo "[Not found]";)
        @echo -n "NPM: " && type npm >/dev/null 2>&1 && echo "[OK]" || (echo "[Not found]";)

make%debug:
        @echo "Application binary name: $(APP_BINARY_NAME)"
        @echo "Application database directory: $(APP_DB_DIR)"
        @echo "Application database generated dump file: $(APP_DB_DIR)/$(APP_DB_DUMP_FILE)"
        @echo "Database listening on localhost@$(DB_PORT): [$(CURRENT_DBSERVER)]"
        @echo "Database using Docker: [$(CURRENT_IS_DBSERVER_DOCKER)]"
