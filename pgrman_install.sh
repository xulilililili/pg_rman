#!/bin/bash
# use root to execute this shell script
# command to execute script : chmod +x pgrman.sh && ./pg_rman.sh
ERROR="\033[41;37m ERROR \033[0m"
INFO="\033[42;37m INFO \033[0m"
WARN="\033[43;37m WARN \033[0m"
COMMON_ERROR="some error happened, specific information please see console output"

current_path=$(pwd)
backup_path=
# Installation package name
package_array=("postgresql10-libs" "pg_rman")
# environment variables
declare -A env_conf_array
env_conf_array=([host]= [data_path]= [backup_path]= [port]= [user]= [password]= )
# pg_rman parameter configuration
declare -A pgrman_conf_array
pgrman_conf_array=([COMPRESS_DATA]=YES [KEEP_ARCLOG_FILES]=7 [KEEP_ARCLOG_DAYS]=7 [KEEP_DATA_GENERATIONS]=3
				[KEEP_DATA_DAYS]=7 [KEEP_SRVLOG_FILES]=7 [KEEP_SRVLOG_DAYS]=7 )

# check command exit value, 0 is success
function check_fun(){
	status=$?
	error=${COMMON_ERROR}
	if [[ 0 -ne ${status} ]] ; then
		echo -e "${ERROR} ${error}"
		exit 1
	fi
}

# read JSON file
function read_json_conf(){
	for key in ${!env_conf_array[*]};
	do
		value=$(grep "${key}" "${current_path}"/pgrman_conf.json | awk -F'"' '{print $4}')
		if [ -z "${value}" ] ; then
			echo -e "${ERROR} failed to read pgrman_conf.json, check if the pgrman_conf.json is configured correctly"
			exit 1
		else 
			env_conf_array[${key}]=${value}
		fi
		backup_path=${env_conf_array['backup_path']}
	done
}

# install pg_rman rpm, need to install postgresql-libs first
function install_pgrman(){
	# support different versions of installation packages
	for((i=0; i<${#package_array[*]}; i++));
	do
		sleep 0.5s
		package_name=$(ls *"${package_array[$i]}"*.rpm )
		if [ -z "${package_name}" ] ; then
			echo -e "${ERROR} installation package ${package_array[$i]} do not exist under the current path"
			echo -e "${INFO} please place installation packages ${package_array[$i]} and scripts in the same path"
			exit 1
		else 
			echo -e "${INFO} installation package name：${package_name}"
			package_array[$i]=${package_name}
		fi
	done
	
	for rpm_name in ${package_array[*]};
	do
		sleep 0.5s
		# remove suffix: '.rpm'
		no_suffix_rpm_name=${rpm_name%'.rpm'}
		# check whether rpm package is installed
		is_install=$(rpm -q "${no_suffix_rpm_name}" | grep -v 'is not installed')
		# install pg-libs and pg_rman
		if [ -z "${is_install}" ] ; then
			rpm -ivh "${rpm_name}"
			echo -e "${INFO} install the ${rpm_name} successfully"
		else
			echo -e "${INFO} ${rpm_name} has been installed, then skip this step"
		fi
	done
}

# configuring environment variables:~/.bashrc
function conf_env(){
	# no check is made to see if parameter has been configured.
	{
	echo "export PG_RMAN=/usr/pgsql-10"
	echo "export PATH=\$PATH:\$PG_RMAN/bin"
	echo "export BACKUP_PATH=${env_conf_array['backup_path']}"
	echo "export PGUSER=${env_conf_array['user']}"
	echo "export PGPASSWORD=${env_conf_array['password']}"
	echo "export PGPORT=${env_conf_array['port']}"
	echo "export PGHOSTADDR=${env_conf_array['host']}"
	echo "export PGDATA=${env_conf_array['data_path']}"
	echo "export ARCLOG_PATH=${env_conf_array['data_path']}/pg_arch"
	echo "export SRVLOG_PATH=${env_conf_array['data_path']}/pg_log"
	} >> ~/.bashrc
	source ~/.bash_profile
}

# initialize the pg_rman,Make a full and incremental backup
function init_pgrman(){
	if [ -d "${backup_path}" ] ; then
		# rm -rf "${backup_path}"
		echo -e "${ERROR} backup_path: ${backup_path} directory already exists"
		exit 1
	fi
	# start to initialize
	pg_rman init
	check_fun
	echo -e "${INFO} initialize the pg_rman successfully"
	sleep 1s
	# modify pg_rman configuration
	for parameter in ${!pgrman_conf_array[*]}
	do
		echo "${parameter} = ${pgrman_conf_array[${parameter}]}" >> "${env_conf_array['backup_path']}"/pg_rman.ini
		check_fun
	done
	echo -e "${INFO} If you want to use incremental backup, you have to make a full backup"
	echo -e "${INFO} start first full backup,please wait patiently"
	# Make a full backup
	pg_rman backup -b full
	check_fun
	pg_rman validate
	echo -e "${INFO} the first full backup successfully"
}

# read JSON files,get parameters
read_json_conf
# install
install_pgrman
# configuring environment variables
conf_env
# initialize the pg_rman
init_pgrman
# add crontab task to automatic backup
if [ ! -f "${current_path}"/pgrman_backup.sh ] ; then
	echo -e "${ERROR} ${current_path}/pgrman_backup.sh, no such file"
	exit 1	
fi
cp "${current_path}"/pgrman_backup.sh "${backup_path}"
check_fun
chmod +x "${backup_path}"/pgrman_backup.sh
# incremental backups are performed every two hours
# full backup is performed every three days
{
	echo "0 */6 * * * ${backup_path}/pgrman_backup.sh incremental"
	echo "0 4 * * * ${backup_path}/pgrman_backup.sh full"
} >> /var/spool/cron/root
