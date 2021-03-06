#!/bin/bash
###################################################################
## Note:
##     Before running this script,must add id_rsa.pub of local host
##     to  ~/.ssh/known_hosts of target host
##
## Reminder:
##      ikbuilder@100.66.0.4 's id_rsa.pub has been add to iktest@100.66.0.4
##      iktest@100.66.0.3,ikuai@58.87.67.57 and ikuai@58.87.74.75
###################################################################
SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)
. ${SHELL_FOLDER}/common.sh


DEPLOY_TARGET_USER=(ikuai)
DEPLOY_TARGET_HOST=(154.8.177.174)
DEPLOY_TARGET_ROOT_DIR=(/home/ikuai/bigdata)


DEPLOY_TARGET_SERVICE=guanzhu
DEPLOY_VERSION=$(basename $0 | cut -d . -f1)


function __deploy_service_to_targets()
{
	local deploy_object=${SHELL_FOLDER}/docker-compose-${DEPLOY_VERSION}.yml
	local count=${#DEPLOY_TARGET_USER[*]}

	for (( i=0; i<count; i++ ))
	do
		local usr=${DEPLOY_TARGET_USER[$i]}
		local host=${DEPLOY_TARGET_HOST[$i]}
		local root_dir=${DEPLOY_TARGET_ROOT_DIR[$i]}

		local target_dir=${root_dir}/${DEPLOY_VERSION}/${DEPLOY_TARGET_SERVICE}
		local target_file=${target_dir}/docker-compose.yml

		__deploy_service ${usr} ${host} ${deploy_object} ${target_dir} ${target_file}
	done
}


function __deploy_ftpserver_to_targets()
{
	local deploy_object=${SHELL_FOLDER}/docker-compose-ftpserver-${DEPLOY_VERSION}.yml
	local count=${#DEPLOY_TARGET_USER[*]}

	for (( i=0; i<count; i++ ))
	do
		local usr=${DEPLOY_TARGET_USER[$i]}
		local host=${DEPLOY_TARGET_HOST[$i]}
		local root_dir=${DEPLOY_TARGET_ROOT_DIR[$i]}

		local target_dir=${root_dir}/${DEPLOY_VERSION}/bigdata_ftp
		local target_file=${target_dir}/docker-compose.yml

		__deploy_service ${usr} ${host} ${deploy_object} ${target_dir} ${target_file}
	done

}

function __deploy_runscripts_to_targets()
{
	local deploy_object=${SHELL_FOLDER}/run_all.sh
	local count=${#DEPLOY_TARGET_USER[*]}

	for (( i=0; i<count; i++ ))
	do
		local usr=${DEPLOY_TARGET_USER[$i]}
		local host=${DEPLOY_TARGET_HOST[$i]}
		local root_dir=${DEPLOY_TARGET_ROOT_DIR[$i]}

		local target_dir=${root_dir}/${DEPLOY_VERSION}/
		local target_file=${target_dir}/run_all.sh

		__deploy_service ${usr} ${host} ${deploy_object} ${target_dir} ${target_file}
	done

}


__deploy_service_to_targets
__deploy_ftpserver_to_targets
__deploy_runscripts_to_targets