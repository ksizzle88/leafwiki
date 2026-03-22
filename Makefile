# Claudio Development Environment
# Usage: make help

.PHONY: build up down shell logs status volumes clean help

TAG ?= local

## Build the base image
build:
	./scripts/build-base.sh --tags $(TAG)

## Start the standalone container (no VS Code)
up:
	docker compose up -d claudio-standalone

## Stop the standalone container
down:
	docker compose down

## Open a shell in the running container
shell:
	@docker compose exec -it devcontainer zsh 2>/dev/null || \
	docker compose exec -it claudio-standalone zsh 2>/dev/null || \
	echo "No running container found. Run 'make up' first."

## View container logs
logs:
	docker compose logs -f --tail=50

## Show container status
status:
	@docker compose ps

## Create all external volumes
volumes:
	./scripts/create-volumes.sh

## Remove stopped containers (keeps volumes)
clean:
	docker compose down --remove-orphans

## Build + start
run: build up

## Show help
help:
	@echo "Claudio Makefile"
	@echo ""
	@echo "  make build        Build claudio-base:$(TAG)"
	@echo "  make up           Start standalone container"
	@echo "  make down         Stop containers"
	@echo "  make shell        Open zsh in running container"
	@echo "  make logs         Tail container logs"
	@echo "  make status       Show container status"
	@echo "  make volumes      Create external volumes"
	@echo "  make clean        Remove stopped containers"
	@echo "  make run          Build + start"
	@echo ""
	@echo "  TAG=local make build   Build with specific tag (default: local)"