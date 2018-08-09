#!/bin/bash

DOCKER_COMPOSE_DIR_LIST=(bigdata_ftp guanzhu)

WORK_PATH=$(pwd)
DOCKER_NETWORK_NAME=bigdata_network

SERVICE_LIST=(ftpserver guanzhu)
BIGDATA_ROOT_DIR=/ikuai/bigdata
LOG_ROOT_DIR=/ikuai/log




function __mk_service_path()
{
	local i=
	local count=${#SERVICE_LIST[*]}
	for ((i=0;i<${count};i++))
	do
		local name=${SERVICE_LIST[$i]}
		local conf_path=${BIGDATA_ROOT_DIR}/${name}/config
		local data_path=${BIGDATA_ROOT_DIR}/${name}/data
		local log_path=${LOG_ROOT_DIR}/${name}

		[ -d "${conf_path}" ] || echo "mk path for ${name}"

		mkdir -p ${conf_path}
		mkdir -p ${data_path}
		mkdir -p ${log_path}
	done
}



function __check_network()
{
	local netname=$1
	local network=`docker network ls  --filter name=^${netname}$ -q`
	[ -n "${network}" ] && return 0 || return 1
}

function __try_create_network()
{ 
	if  __check_network ${DOCKER_NETWORK_NAME} ;then
		echo "${DOCKER_NETWORK_NAME} is ready"
		return
	fi

	if ! docker network create  ${DOCKER_NETWORK_NAME};then
		echo "create  ${DOCKER_NETWORK_NAME} network failed"
		exit 1
	fi

	local wait_seconds=5
	while [ "$((wait_seconds--))" -gt 0 ];do
		sleep 1
		if __check_network ${DOCKER_NETWORK_NAME} ;then
			echo "create ${DOCKER_NETWORK_NAME} ok"
			return
		fi
	done

	echo "create  ${DOCKER_NETWORK_NAME} network failed"
	exit 2
}


function __start_services()
{
	local i=
	local count=${#DOCKER_COMPOSE_DIR_LIST[*]}
	echo "WorkPath=${WORK_PATH},need start ${count} docker-compose"

	for ((i=0;i<${count};i++))
	do
		local name=${DOCKER_COMPOSE_DIR_LIST[$i]}
		local path=${WORK_PATH}/${name}
		cd ${path}

		if docker-compose pull &&  ! docker-compose up -d ;then
			echo "start docker-compose in ${name} failed !!!"
			cd ${WORK_PATH}
			exit 3
		fi
		echo "start ${name} OK"
	done

	cd ${WORK_PATH}

}


function __stop_services()
{
	local i=
	local count=${#DOCKER_COMPOSE_DIR_LIST[*]}

	for ((i=0;i<${count};i++))
	do
		local name=${DOCKER_COMPOSE_DIR_LIST[$i]}
		local path=${WORK_PATH}/${name}
		cd ${path}

		if ! docker-compose down ;then
			echo "stop docker-compose in ${name} failed"
		fi

	done

	cd ${WORK_PATH}

}



case "$1" in
	stop)
		__stop_services
		;;
	start)
		__start_services
		;;
	restart)
		__stop_services
		sleep 3
		__start_services
		;;
	init)
		__mk_service_path
		__try_create_network
		;;
		*)
		__mk_service_path
		__try_create_network
		__start_services
		;;
esac
