

function __log_error()
{
	printf "\033[41;37m[error] ${1} \033[0m \n"
}

function __log_info()
{
	printf "\033[38;33m[info] ${1} \033[0m \n"
}

function __log_ok()
{
	printf "\033[46;31m[ok] ${1} \033[0m \n"
}



function __mk_target_dir()
{
	local usr=$1
	local host=$2
	local target_dir=$3

	if ! ssh ${usr}@${host} "[ -d ${target_dir} ] && echo Not need mkdir || mkdir -p ${target_dir} ";then
		__log_error "Create ${target_dir}  >>> Failed"
		return 1
	fi

	__log_info "Create ${target_dir} >>> OK"
	return 0
}

function __deploy_object()
{
	local usr=$1
	local host=$2
	local object=$3
	local target=$4

	if ! scp ${object} ${usr}@${host}:${target} ;then
		__log_error "Deploy  ${object} to ${target} >>> Failed"
		return 2
	fi

	__log_info "Deploy ${object} to ${target} >>> OK"
	return 0
}


######################################
### deploy file to target host
### $1 --> user
### $2 --> host
### $3 --> source file(full path)
### $4 --> target dir
### $5 --> target file(full path)
######################################
function __deploy_service()
{
	local usr=$1
	local host=$2
	local object=$3
	local target_dir=$4
	local target_file=$5

	__log_info "Start deploy service to ${host}:${target_dir}"

	__mk_target_dir ${usr} ${host} ${target_dir} || exit 1
	__deploy_object ${usr} ${host} ${object} ${target_file} || exit 2

	__log_ok "Finish deploy ${object} to ${usr}@${host}"

}
