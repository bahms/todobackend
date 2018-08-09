PROJECT_NAME ?= todobackend
ORG_NAME ?= bahms
REPO_NAME ?= todobackend

DEV_COMPOSE_FILE := docker/dev/docker-compose.yml
REL_COMPOSE_FILE := docker/release/docker-compose.yml

REL_PROJECT = $(PROJECT_NAME)$(BUILD_ID)
DEV_PROJECT = $(PROJECT_NAME)dev

INSPECT := $$(docker-compose -p $$1 -f $$2 ps -q $$3 | xargs -I ARGS docker inspect -f "{{ .State.ExitCode }}" ARGS)

CHECK := @bash -c 'if [[ $(INSPECT) -ne 0 ]]; then exit $(INSPECT); fi' VALUE

.PHONY: test build release clean

test:
	${INFO} "Building images..."
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) build
	${INFO} "Waiting for the database to be ready"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) run --rm agent
	${INFO} "Running tests"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) up test
	docker cp $$(docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) ps -q test):/reports/. report
	${CHECK} $(DEV_PROJECT) $(DEV_COMPOSE_FILE) test
	${INFO} "Testing complete"

build:
	${INFO} "Building app artifacts"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) up builder
#artifacts copied only when the build is ok
	${CHECK} $(DEV_PROJECT) $(DEV_COMPOSE_FILE) builder
	${INFO} "Copying artifacts to target folder..."
	docker cp $$(docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) ps -q builder):/wheelhouse/. target
	${INFO} "Build complete"

release:
	${INFO} "Starting release phase"
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) build
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) run --rm agent
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) run --rm app manage.py collectstatic --noinput
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) run --rm app manage.py migrate --noinput
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) up test
	docker cp $$(docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) ps -q test):/reports/. reports
	${CHECK} $(REL_PROJECT) $(REL_COMPOSE_FILE) test
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
