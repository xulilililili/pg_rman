#!/bin/bash
#command to execute script: su - postgres -c "./create.sh"
#default value refer to standard server(cpu:4cores,memory:32G,storage:12T)
#value according to the actual situation 

#List of parameters to be modified
:<<!
	enable_seqscan = off
	enable_indexscan = on
	enable_bitmapscan = on
	max_connections = 1000
	shared_buffers = 8GB
	effective_cache_size = 16GB
	work_mem = 64MB
	wal_buffers = 32MB
	maintenance_work_mem = 512MB
	log_destination = csvlog
	log_directory = pg_log
	logging_collector = on
	log_min_duration_statement = 800
	log_rotation_size = 1024MB
	log_truncate_on_rotation = on
	log_filename = 'viid_log_%a.log'
	archive_mode = on
	archive_command = "cp %p ${data_directory}/pg_arch/%f"
!

ERROR="\033[41;37m ERROR \033[0m"
INFO="\033[42;37m INFO \033[0m"
WARN="\033[43;37m WARN \033[0m"
COMMON_ERROR="some error happened, specific information please see console output"

# Array of parameters
declare -A parameter_array
parameter_array=([enable_seqscan]=off [enable_indexscan]=on [enable_bitmapscan]=on [max_connections]=1000 [shared_buffers]=8GB 
[effective_cache_size]=16GB [work_mem]=64MB [wal_buffers]=32MB [maintenance_work_mem]=512MB [log_destination]=csvlog [log_directory]=pg_log [logging_collector]=on [log_min_duration_statement]=800 [log_rotation_size]=1024MB [log_truncate_on_rotation]=on 
[log_filename]=viid_log_%a.log [archive_mode]=on [archive_command]= )

#default value :
pgctl_path=
data_directory=
memory=

# check command exit value, 0 is success
function check_fun(){
	status=$?
	error=${COMMON_ERROR}
	if [[ -n $1 ]] ; then
        error=$1
    fi
	if [[ 0 -ne ${status} ]] ; then
		echo -e "${ERROR} ${error}"
		exit 1
	fi
}

# prepare conditions
function prepare_conditions(){
	data_directory=$(psql -qtAX  -c "show data_directory" | sed 's/[ ]//g')
	check_fun
	if [ ! -d "${data_directory}" ];then
		echo -e "${ERROR} database's data directory does not exist"
		exit 1
	fi
	# physical machine environment
	memory=$(grep MemTotal /proc/meminfo | awk '{print $2 / 1024 / 1024}' | sed 's/\.[0-9]*//' | tail -n 1)
	check_fun
	# docker environment 
	memory_limit=$(($(awk '{print $1}' /sys/fs/cgroup/memory/memory.limit_in_bytes) / 1024 / 1024 /1024))
	check_fun
	# comparing the two, choose the smaller one.
	if [ "${memory_limit}" -le "${memory}" ];then
		memory=${memory_limit}
	fi
}

# calculate parameters
function calculate_parameters(){
	# 50%*memory
	parameter_array[effective_cache_size]=$((memory * 1024 / 2))"MB"
	# 25%*memory
	parameter_array[shared_buffers]=$((memory * 1024 / 4))"MB"
	# around 1%*memory 
	parameter_array[work_mem]=$((memory * 1024 / 128))"MB"
	# 32GB => 512MB
	parameter_array[maintenance_work_mem]=$((memory * 16 ))"MB"
	# cp %p ${data_directory}/pg_arch/%f
	parameter_array[archive_command]="cp %p ${data_directory}/pg_arch/%f"
}

# modify parameters
function modify_parameters(){
	# modify parameters by modifying file postgresql.conf:
	for parameter in ${!parameter_array[*]}
	do
		#check whether the parameters have been modified
		# PostgreSQL's default parameter configuration example: enable_seqscan = on
		# viid's example: enable_seqscan='on'
		check_out=$(grep "^${parameter}=" "${data_directory}"/postgresql.conf | grep -v '#' | tail -n 1)
		# process sleep 
		sleep 0.2s
		if [ -z "${check_out}" ];then
			echo "${parameter}='${parameter_array[${parameter}]}'" >> "${data_directory}"/postgresql.conf
			check_fun
			echo -e "${INFO} modify ${parameter} successfully"
		else 
			if [ "${check_out}" = "${parameter}='${parameter_array[${parameter}]}'" ];then
				echo -e "${INFO} ${parameter} is already configured, then skip this step"
			else
				sed -i s!^"${check_out}"!"${parameter}='${parameter_array[${parameter}]}'"!g  "${data_directory}"/postgresql.conf
				check_fun
				echo -e "${INFO} modify ${parameter} successfully"
			fi
		fi
	done
}

# create directory(pg_log and pg_arch), and set user postgres permission
function create_dir(){
	directory_array=("pg_arch" "pg_log")
	for directory in ${directory_array[*]};
	do
		# process sleep 
		sleep 0.2s
		if [ ! -d "${data_directory}/${directory}" ];then
			mkdir -p "${data_directory}"/"${directory}"
			echo -e "${INFO} path ${data_directory}/${directory} create successfully"
		else 
			echo -e "${INFO} ${data_directory}/${directory} is already exists, then skip this step"
		fi
	# set user postgres permission
	chown postgres:postgres "${data_directory}"/"${directory}"
	done
}

# because the environment is different, need to find the path of the database restart command 'pg_ctl'
function find_cmd(){
	result=$(find / -name pg_ctl 2> /dev/null | grep bin/pg_ctl$ | tail -n 1 )
	# check whether the path exists 
	if [ -z "${result}" ];then 
		echo -e "${ERROR} database restart command 'pg_ctl' not exists"
		echo -e "${ERROR} please check to see if the database is installed or the command directory does not have permission to access it"
		exit 1
	else 
		echo -e "${INFO} database restart command 'pg_ctl' path: ${result}"
		pgctl_path=${result}
	fi
}

# user choose whether to restart or not 
function check_restart(){
	read -r -p "Is it necessary to restart database immediately?[Enter YES or NO]:" result
	if [ "${result,,}" = "yes" ] ; then 
		echo -e "${INFO} start to restart database"
		${pgctl_path} restart -D "${data_directory}" >& /dev/null
		if [[ 0 -ne ${status} ]] ; then
			echo -e "${ERROR} restart database failed"
			exit 12
		fi
	elif [ "${result,,}" = "no" ] ; then 
		echo -e "${WARN} please restart database manually"
		echo -e "${WARN} if you don't restart, database may not be available"
		exit 11
	else
		echo -e "${ERROR} invalid input,please enter again"
		check_restart
	fi
}

# ******* start *******
# prepare conditions:memory ,data_directory
prepare_conditions
# calculate parameters
calculate_parameters
# modify parameters
modify_parameters 
# create directory(pg_log and pg_arch)
create_dir
# the path of the database restart command 'pg_ctl'
find_cmd
# remind user that they need to restart database to take effect
# process sleep 
sleep 0.5s
echo -e ""
echo -e "*******************************************************************"
echo -e "*                                                                 *"
echo -e "*                                                                 *"
echo -e "*                restart database to take effect                  *"
echo -e "*                                                                 *"
echo -e "*                                                                 *"
echo -e "*******************************************************************"
# process sleep 
sleep 0.5s
# user choose whether to restart or not 
check_restart

