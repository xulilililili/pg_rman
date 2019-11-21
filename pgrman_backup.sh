#!/bin/bash
# use root to execute this shell script

# level
ERROR="\033[41;37m ERROR \033[0m"
INFO="\033[42;37m INFO \033[0m"
WARN="\033[43;37m WARN \033[0m"
COMMON_ERROR="some error happened, specific information please see console output"

source ~/.bash_profile
# postgresql data directory
# pgdata=$(grep 'PGDATA' ~/.bashrc |awk -F= '{print $2}')
# backup directory
backup_path=$(grep 'BACKUP_PATH' ~/.bashrc | tail -n 1 | awk -F= '{print $2}')
# log file
backup_log=${backup_path}/backup_log/backup_$(date +'%Y%m%d').log
# backup type:{full|incremental}
backup_type=$1

# check command exit value, 0 is success
function check_fun(){
	status=$?
	error=${COMMON_ERROR}
	if [[ 0 -ne ${status} ]] ; then
		echo -e "${ERROR} ${error}"
		exit 1
	fi
}

# create new log every day 
# log format:backup_yyyyMMdd
function create_log(){
	if [ ! -d "${backup_path}"/backup_log ] ; then
		mkdir -p "${backup_path}"/backup_log
		check_fun
	fi
	if [ ! -f "${backup_log}" ] ; then
		touch "${backup_log}"
		check_fun
	fi
	# delete logs 7 days ago
	find "${backup_path}"/backup_log/ -mtime +6 -name "*.log" -exec rm -Rf {} \;
	check_fun
}

# backup :1.full 2.incremental
function backup(){
	case "${backup_type}" in
		incremental)
			pg_rman backup -b incremental &>> "${backup_log}"
			check_fun
			;;
		full)
			pg_rman backup -b full &>> "${backup_log}"
			check_fun
			;;
		*)
			echo -e "$(date +'%Y-%m-%d %H:%M:%S'): ${ERROR} uthe value of the type is only incremental or full"  >> "${backup_log}"
			exit 1
	esac
	# backup set check
	pg_rman validate &>> "${backup_log}"
	check_fun
	# clean up invalid backup data
	pg_rman purge &>> "${backup_log}"
	check_fun
}

# create new log every day 
create_log
start_time=$(date +%s)
echo -e "$(date +'%Y-%m-%d %H:%M:%S'): ${INFO} start ${backup_type} backup" >> "${backup_log}"
# backup 
backup
end_time=$(date +%s)
echo -e "$(date +'%Y-%m-%d %H:%M:%S'): ${INFO} ${backup_type} backup end" >> "${backup_log}"
echo -e "$(date +'%Y-%m-%d %H:%M:%S'): ${INFO} total backup time: "$((end_time-start_time))"s" >> "${backup_log}"
echo -e "" "${backup_log}"

