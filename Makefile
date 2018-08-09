all:build
.PHONY : all  help clean docker test run release deploy save

BUILD_ROOT :=$(shell pwd)
include $(BUILD_ROOT)/common.mk

PKG_VERSION	:= 1.0.0
PKG_NAME	:= infrastructure

### docker path includes: deploy,dev or other
DOCKER_PATH ?= deploy

## deploy includes: dev,test,release or other
DEPLOY_TARGET ?= dev
DEPLOY_SCRIPT := deploy/$(DEPLOY_TARGET).sh

BIN_DIR    :=
OUT_PUT    := $(BIN_DIR)

export  BUILD_ROOT
export	OUT_PUT
export	BUILD_VERSION=${PKG_VERSION}

SUBDIRS := $(wildcard src/*)
DOCKER_SUBDIRS := $(wildcard docker/*)
DEPLOY_SOURCES := $(wildcard deploy/*)
PHONY_DEPLOY_SRC := phony_deploy_$(DEPLOY_TARGET)



build:$(SUBDIRS)  .toolchain
	for dir in $(SUBDIRS);\
	do $(MAKE) -C $$dir   all ||exit 1;\
	done

clean-tools:
	rm -f .toolchain

clean-docker:
	for dir in $(DOCKER_SUBDIRS);\
	do $(MAKE) -C $$dir clean-docker;\
	done


clean:
	for dir in $(SUBDIRS);\
	do $(MAKE) -C $$dir clean;\
	done


clean-none:
	docker rmi $$(docker images -f "dangling=true" -q)


clean-deploy:clean-docker
	rm -f .$(PHONY_DEPLOY_SRC)


docker:build
	for dir in $(DOCKER_SUBDIRS);\
	do $(MAKE) -C $$dir   docker DOCKER_PATH=$(DOCKER_PATH) ||exit 1;\
	done



deploy:deploy-docker  .$(PHONY_DEPLOY_SRC)
	@:

deploy-docker:docker
	for dir in $(DOCKER_SUBDIRS);\
	do $(MAKE) -C $$dir   deploy DOCKER_PATH=$(DOCKER_PATH) ||exit 1;\
	done

.$(PHONY_DEPLOY_SRC):$(DEPLOY_SOURCES)
ifeq ($(DEPLOY_SCRIPT), $(wildcard $(DEPLOY_SCRIPT)))
	$(DEPLOY_SCRIPT)
	@[ $$? -eq 0 ] && touch $@
	$(call log_info2,"deploy docker-compose.yml by $(DEPLOY_SCRIPT)")
else
	$(call log_warn,"No $(DEPLOY_SCRIPT)")
endif



save:
	for dir in $(DOCKER_SUBDIRS);\
	do $(MAKE) -C $$dir  save DOCKER_PATH=$(DOCKER_PATH) ||exit 1;\
	done

run:
	for dir in $(DOCKER_SUBDIRS);\
	do $(MAKE) -C $$dir   run DOCKER_PATH=$(DOCKER_PATH) ||exit 1;\
	done

test:
	$(MAKE) -C docker/stats_analyse  test


tools:.toolchain
	@:

.toolchain:
	$(call log_info,"At present no toolchain")
	@[ $$? -eq 0 ] && touch $@

help:
	@printf "all/build\t- only build bin\n"
	@printf "tools\t\t- create tools-chains (docker)\n"
	@printf "clean \t\t- clean the bin\n"
	@printf "clean-tools \t\t- clean tools .etc for make tools\n"
	@printf "clean-docker \t\t- clean docker for make docker\n"
	@printf "clean-deploy \t\t-clean some deploy files\n"
	@printf "docker \t\t- build docker image,e.g make DOCKER_PATH=dev docker\n"
	@printf "deploy \t\t- push image and tar data,e.g make docker\n"
	@printf "save \t\t- save and tar image to local\n"
	@printf "run \t\t- run docker at local for test\n"
	@printf "test \t\t- run a docker for test\n"
