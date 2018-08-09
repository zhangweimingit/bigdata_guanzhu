DOCKER_REPERTORY ?= dockers.ikuai8.com
DOCKER_PATH      ?= dev
COMMIT_SHA1      := $(shell  git rev-parse HEAD 2>/dev/null)




# $(1): info (YELLOW_BLUE)
define log_info 
	@printf "\033[38;33m"$(1)" \033[0m \n"
endef


# $(1): info (GREEN_WHITE)
define log_info2 
	@printf "\033[42;37m"$(1)" \033[0m \n"
endef

# $(1): warn info (WHITE_RED)
define log_warn 
	@printf "\033[47;31m[warning] "$(1)" \033[0m \n"
endef


# $(1): error info (RED_WHITE)
define log_error 
	@printf "\033[41;37m[error] "$(1)" \033[0m \n"
endef

