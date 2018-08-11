PROJECT_NAME ?= todobackend
ORG_NAME ?= bahms
REPO_NAME ?= todobackend

DEV_COMPOSE_FILE := docker/dev/docker-compose.yml
REL_COMPOSE_FILE := docker/release/docker-compose.yml

REL_PROJECT = $(PROJECT_NAME)$(BUILD_ID)
DEV_PROJECT = $(PROJECT_NAME)dev

INSPECT := $$(docker-compose -p $$1 -f $$2 ps -q $$3 | xargs -I ARGS docker inspect -f "{{ .State.ExitCode }}" ARGS)

CHECK := @bash -c 'if [[ $(INSPECT) -ne 0 ]]; then exit $(INSPECT); fi' VALUE

DOCKER_REGISTRY ?= docker.io

APP_SERVICE_NAME := app
BUILD_TAG_EXPRESSION ?= date -u +%Y%m%d%H%M%S
BUILD_EXPRESSION := $(shell $(BUILD_TAG_EXPRESSION))
BUILD_TAG ?= $(BUILD_EXPRESSION)

DOCKER_REGISTRY_AUTH ?=

.PHONY: test build release clean tag login logout publish

test:
	${INFO} "CReating cache volume..."
	@ docker volume create --name cache
	${INFO} "Pulling latest images"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) pull
	${INFO} "Building images..."
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) build --pull test
	${INFO} "Waiting for the database to be ready"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) run --rm agent
	${INFO} "Running tests"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) up test
	docker cp $$(docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) ps -q test):/reports/. reports
	${CHECK} $(DEV_PROJECT) $(DEV_COMPOSE_FILE) test
	${INFO} "Testing complete"

build:
	${INFO} "Creating builder image..."
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) build builder
	${INFO} "Building app artifacts"
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) up builder
#artifacts copied only when the build is ok
	${CHECK} $(DEV_PROJECT) $(DEV_COMPOSE_FILE) builder
	${INFO} "Copying artifacts to target folder..."
	docker cp $$(docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) ps -q builder):/wheelhouse/. target
	${INFO} "Build complete"

release:
	${INFO} "Pulling latest images..."
	@docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) pull test
	${INFO} "Builing images..."
	@docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) build app
	@docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) build --pull nginx
	${INFO} "Starting release phase"
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) run --rm agent
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) run --rm app manage.py collectstatic --noinput
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) run --rm app manage.py migrate --noinput
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) up test
	${INFO} "********SLEEP*********"
	sleep $$SLEEP_RETRY 
	docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) up test
	docker cp $$(docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) ps -q test):/reports/. reports
	${CHECK} $(REL_PROJECT) $(REL_COMPOSE_FILE) test
	${INFO} "Release phase (Acceptance tests complete)"
clean:
	${INFO} "Start cleaning..."
	@docker-compose -p $(DEV_PROJECT) -f $(DEV_COMPOSE_FILE) down
	@docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) down
	@docker images -q -f dangling=true -f label=application=$(REPO_NAME) | xargs -I ARGS docker rmi -f ARGS
	${INFO} "Cleaning ok"

tag:
	${INFO} "Tagging release images with tags $(TAG_ARGS)..."
	@ $(foreach tag, $(TAG_ARGS), docker tag $(IMAGE_ID) $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME):$(tag) ); 
	${INFO} "Tagging complete"

buildtag:
	${INFO} "Tagging release image with suffix $(BUILD_TAG) and build tags $(BUILDTAG_ARGS)..."
	@ $(foreach tag,$(BUILDTAG_ARGS), docker tag $(IMAGE_ID) $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME):$(tag).$(BUILD_TAG);)
	${INFO} "Tagging complete"

login:
	${INFO} "Logging in to Docker registry $$DOCKER_REGISTRY..."
	@ docker login -u $$DOCKER_USER -p $$DOCKER_PASSWORD $(DOCKER_REGISTRY_AUTH)
	${INFO} "Logged in to Docker registry $$DOCKER_REGISTRY"

logout:
	${INFO} "Logging out of Docker registry $$DOCKER_REGISTRY..."
	@ docker logout
	${INFO} "Logged out of Docker registry $$DOCKER_REGISTRY"	

publish:
	${INFO} "Publishing release image $(IMAGE_ID) to $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME)..."
	@ $(foreach tag,$(shell echo $(REPO_EXPR)), docker push $(tag);)
	${INFO} "Publish complete"

#text in bold ([1) AND YELLOW (33m)
YELLOW := "\e[1;33m" 
NO_COLOR := "\e[0m"

INFO := @bash -c 'printf $(YELLOW); echo "=> $$1"; printf $(NO_COLOR)' VALUE

APP_CONTAINER_ID := $$(docker-compose -p $(REL_PROJECT) -f $(REL_COMPOSE_FILE) ps -q $(APP_SERVICE_NAME))
IMAGE_ID := $$(docker inspect -f '{{ .Image }}' $(APP_CONTAINER_ID))


ifeq ($(DOCKER_REGISTRY), docker.io)
	REPO_FILTER := $(ORG_NAME)/$(REPO_NAME)[^[:space:]|\$$]*
else
	REPO_FILTER := $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME)[^[:space:]|\$$]*
endif

REPO_EXPR := $$(docker inspect -f '{{range .RepoTags}}{{.}} {{end}}' $(IMAGE_ID) | grep -oh "$(REPO_FILTER)" | xargs)

ifeq (buildtag,$(firstword $(MAKECMDGOALS)))
	BUILDTAG_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  ifeq ($(BUILDTAG_ARGS),)
  	$(error You must specify a tag)
  endif
  $(eval $(BUILDTAG_ARGS):;@:)
endif


ifeq (tag,$(firstword $(MAKECMDGOALS)))
  TAG_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  ifeq ($(TAG_ARGS),)
    $(error You must specify a tag)
  endif
  $(eval $(TAG_ARGS):;@:)
endif



