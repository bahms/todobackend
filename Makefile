PROJECT_NAME ?= todobackend
ORG_NAME ?= bahms
REPO_NAME ?= todobackend

DEV_COMPOSE_FILE := docker/dev/docker-compose.yml
REL_COMPOSE_FILE := docker/release/docker-compose.yml

REL_PROJECT = $(PROJECT_NAME)$(BUILD_ID)
DEV_PROJECT = $(PROJECT_NAME)dev

.PHONY: test build release clean

test:
	${INFO} "Building images..."
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) build
	${INFO} "Waiting for the database to be ready"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) up agent
	${INFO} "Running tests"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) up test
	${INFO} "Testing complete"

build:
	${INFO} "Building app artifacts"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) up builder
	${INFO} "Build complete"

release:
	${INFO} "Starting release phase"
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) build
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) up agent
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) run --rm app manage.py collectstatic --noinput
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) run --rm app manage.py migrate --noinput
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) up test
	${INFO} "Release phase (Acceptance tests complete)"
clean:
	${INFO} "Start cleaning..."
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) kill
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) rm -f -v
	@docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) kill
	@docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) rm -f -v
	@docker images -q -f dangling=true -f label=application=$(REPO_NAME) | xargs -I ARGS docker rmi -f ARGS
	${INFO} "Cleaning ok"

#text in bold ([1) AND YELLOW (33m)
YELLOW := "\e[1;33m" 
NO_COLOR := "\e[0m"

INFO := @bash -c 'printf $(YELLOW); echo "=> $$1"; printf $(NO_COLOR)' VALUE
