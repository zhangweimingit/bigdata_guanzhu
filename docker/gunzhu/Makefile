all:docker
.PHONY : all  help clean docker test run release deploy

BUILD_ROOT ?= ../..
include $(BUILD_ROOT)/common.mk

## Before releasing, need change the version number
DOCKER_VERSION	:= 1.0.0
DOCKER_IMG_NAME	:= guanzhu
DOCKER_IMAGE := $(DOCKER_REPERTORY)/$(DOCKER_PATH)/$(DOCKER_IMG_NAME):${DOCKER_VERSION}
DOCKER_PHONY_IMAGE := phony_docker_$(DOCKER_REPERTORY)_$(DOCKER_PATH)_$(DOCKER_IMG_NAME)_${DOCKER_VERSION}
SOURCES := ./Dockerfile ./nginx.conf $(wildcard ./lua/*)


docker:.${DOCKER_PHONY_IMAGE}
	@:


.${DOCKER_PHONY_IMAGE}:${SOURCES}
	$(call log_info,"Start to build docker >>> $(DOCKER_IMAGE)")
	docker build --rm  -t $(DOCKER_IMAGE) $(shell pwd)
	@[ $$? -eq 0 ] && touch $@
	$(call log_info,"build docker >>> $(DOCKER_IMAGE)")
	$(call log_info,"Finish building docker >>> $(DOCKER_IMAGE)")


deploy:.deploy
	@:


.deploy:.${DOCKER_PHONY_IMAGE}
	docker push $(DOCKER_IMAGE)
	@[ $$? -eq 0 ] && touch $@
	$(call log_info2,"push docker >>> $(DOCKER_IMAGE)")

clean-docker:
	rm -f .${DOCKER_PHONY_IMAGE}
	rm -f .deploy


save:
	@echo "TODO:No save"


run:
	docker run -ti --rm  --name $(DOCKER_IMG_NAME)   \
	-p 8088:80 \
	-v /ikuai/bigdata/guanzhu/data:/service/data -v /ikuai/bigdata/guanzhu/config:/service/config \
	-v /ikuai/log/guanzhu:/usr/local/openresty/nginx/logs -v /etc/localtime:/etc/localtime:ro \
	-v /ikuai/bigdata/ftpserver/data:/home/bigdata \
	$(DOCKER_IMAGE) sh

##entry docker--->  /usr/local/openresty/bin/openresty

test:
	$(call log_warn,"This is sample,need revise!!!")
	docker run -it --rm --name test_$(DOCKER_IMG_NAME) --link=$(DOCKER_IMG_NAME) \
	-v ${BUILD_ROOT}/test:/test \
	-w /test \
	sequenceiq/busybox bash


help:
	@printf "all/docker \t\t- build docker image,e.g make DOCKER_PATH=dev docker\n"
	@printf "deploy \t\t- push image and tar data,e.g make docker\n"
	@printf "save \t\t- save and tar image to local\n"
	@printf "run \t\t- run docker at local for test\n"
	@printf "test \t\t- run a docker for test\n"
