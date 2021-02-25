#!/bin/bash
#: Title		:host-config-backup.sh
#: Date			:2021-02-06
#: Author		:"Damola Adebayo"
#: Version		:1.0
#: Description	:use to create backup copy (ie one-way) of various system-specific files
#: Description	:such as configuration files that aren't covered by the routine backups
#: Description	:of the working directories. files are --update copied to external device if
#: Description	:possible, else to a local sychronised directory.
#: Options		:None

###############################################################################################
# This program is concerned only with files that are not synchronised along with the frequently mutating files, \
# since they are DIFFERENT on each host and/or they're not accessible by regular user permissions. \
# For example:
	# configuration files
	# HOME, Downloads... dirs

# This program only needs to try to run say, once every day, as these configuration and 
# host-specific files change less frequently.

# This program is only concerned with getting current copies of these files onto external drive, or \
# into sync-ready position on respective hosts. That's it. CRON makes this happen daily.

# The program branches based on whether interactive shell.

# on bash:
# m h  dom mon dow   command
# 30 12,16 * * * * /usr/bin/time -a -o "/home/dir/hcf-log" /path/to/git/repo/host-config-backup.sh

# Needs to run as root to get access to those global configuration files
# then adjust file ownership or not?

# To add a new file path to this program, we just add it to the json configuration file.

# NOTE: new cp --update strategy assumes that existing source files get modified or not, but don't get deleted.
# ...so need a way to get rid of last CURRENT backup of a deleted file.

# host authorisation is moot because configuration file specifies host-specific configuration parameters 
###############################################################################################

function main 
{
	###############################################################################################
	# GLOBAL VARIABLE DECLARATIONS:
	###############################################################################################
	
	## EXIT CODES:
	export E_UNEXPECTED_BRANCH_ENTERED=10
	export E_OUT_OF_BOUNDS_BRANCH_ENTERED=11
	export E_INCORRECT_NUMBER_OF_ARGS=12
	export E_UNEXPECTED_ARG_VALUE=13
	export E_REQUIRED_FILE_NOT_FOUND=20
	export E_REQUIRED_PROGRAM_NOT_FOUND=21
	export E_UNKNOWN_RUN_MODE=30
	export E_UNKNOWN_EXECUTION_MODE=31
	export E_FILE_NOT_ACCESSIBLE=40
	export E_UNKNOWN_ERROR=32

	#######################################################################
	declare -r PROGRAM_PARAM_1=${1:-"not_yet_set"} ## 

	declare -i MAX_EXPECTED_NO_OF_PROGRAM_PARAMETERS=1
	declare -ir ACTUAL_NO_OF_PROGRAM_PARAMETERS=$#
	ALL_THE_PARAMETERS_STRING="$@"

	CONFIG_FILE_FULLPATH=

	# declare the backup scheme for which this backup program is designed
	declare -r BACKUP_SCHEME_TYPE="host_configuration_file_backups"
	# declare the constant identifying the current host
	declare -r THIS_HOST="$(hostname)"

	DST_BACKUP_DIR_EXTERNAL=
	DST_BACKUP_DIR_LOCAL=
	dst_dir_current_fullpath=

	BACKUP_DESCRIPTION=
	REGULAR_USER=
	REGULAR_USER_HOME_DIR=
	declare -a SRC_FILES_FULLPATHS_LIST=()
	declare -a EXCLUDED_FILES_FULLPATHS_LIST=()
	LOG_FILE=
	
	ABS_FILEPATH_REGEX='^(/{1}[A-Za-z0-9\.\ _~:@-]+)+/?$' # absolute file path, ASSUMING NOT HIDDEN FILE, ...
	REL_FILEPATH_REGEX='^(/?[A-Za-z0-9\.\ _~:@-]+)+(/)?$' # relative file part-path, before trimming

	test_line="" # global...


	
	
	###############################################################################################


	# establish the script RUN_MODE using whoami command.
	if [ $(whoami) == "root" ]
	then
		declare -r RUN_MODE="batch"
		#make_root_safe by making
	else
		declare -r RUN_MODE="interactive"
	fi

	# count program positional parameters
	check_no_of_program_args

	echo "OUR CURRENT SHELL LEVEL IS: $SHLVL"

	if [ $SHLVL -le 3 ]
	then
		# Display a descriptive and informational program header:
		display_program_header

		# give user option to leave if here in error:
		if [ $RUN_MODE == "interactive" ]
		then
			get_user_permission_to_proceed
		fi
	fi

	# cleanup and validate, test program positional parameters
	cleanup_and_validate_program_arguments
	
	#exit 0 # debug

	
	###############################################################################################
	# PROGRAM-SPECIFIC FUNCTION CALLS:	
	###############################################################################################

	if [ -n "$CONFIG_FILE_FULLPATH" ]
	then
		echo "the config is REAL"
		#display_current_config_file
		import_json
	else
		msg="NO CONFIG FOR YOU, returned code: $return_code. Exiting now..."
		exit_with_error "$E_REQUIRED_FILE_NOT_FOUND" "$msg" 	

	fi
	
	setup_dst_dirs

	exit 0 # debug


	backup_regulars_and_dirs

	change_file_ownerships

	report_summary
	

} ## end main




###############################################################################################
####  FUNCTION DECLARATIONS  
###############################################################################################

function import_json() 
{
	HOST_BACKUP_DATA_STRING=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg THIS_HOST "$THIS_HOST" '.hosts[] | select(.hostname==$THIS_HOST) | .[]') 

	echo $HOST_BACKUP_DATA_STRING
	echo && echo

	# easier to assign values to program variables using this LOCAL bash array structure
	declare -a HOST_BACKUP_DATA_ARRAY=( $HOST_BACKUP_DATA_STRING )
	
	#
	DST_BACKUP_DIR_EXTERNAL="${HOST_BACKUP_DATA_ARRAY[1]}"
	DST_BACKUP_DIR_LOCAL="${HOST_BACKUP_DATA_ARRAY[2]}"
	# 	# TODO: generalise cleanup_and_validate_program_arguments

	
	echo "$DST_BACKUP_DIR_EXTERNAL"
	echo "$DST_BACKUP_DIR_LOCAL"
	echo && echo "###########" && echo

	########

	# jq -r leaves sentences unqoted, so data would have to escape-quote
	#BACKUP_SCHEME_DATA_STRING=$(cat "$CONFIG_FILE_FULLPATH" | jq --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backup_schemes[] | select(.backup_type==$BACKUP_SCHEME_TYPE) | .[]')

	#echo $BACKUP_SCHEME_DATA_STRING && echo



	######## FIRST... ASSIGNING THE JSON ARRAY DATA TO CORRESPONDING BASH ARRAY DATA STRUCTURES...


	SRC_FILES_FULLPATHS_STRING=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backup_schemes[] | select(.backup_type==$BACKUP_SCHEME_TYPE) | .src_files_fullpaths[]')

	echo $SRC_FILES_FULLPATHS_STRING

	SRC_FILES_FULLPATHS_LIST=( $SRC_FILES_FULLPATHS_STRING )
	# cleanup_and_validate_program_arguments
	echo && echo "###########" && echo

	########

	EXCLUDED_FILES_FULLPATHS_STRING=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backup_schemes[] | select(.backup_type==$BACKUP_SCHEME_TYPE) | .excluded_files_fullpaths[]')

	echo $EXCLUDED_FILES_FULLPATHS_STRING

	EXCLUDED_FILES_FULLPATHS_LIST=( $EXCLUDED_FILES_FULLPATHS_STRING )
	# cleanup_and_validate_program_arguments
	echo && echo "###########" && echo



	######## NEXT... ASSIGNING THE JSON VALUES DATA TO CORRESPONDING BASH SCALAR VARIABLES...



	BACKUP_DESCRIPTION=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backup_schemes[] | select(.backup_type==$BACKUP_SCHEME_TYPE) | .backup_description')

	# cleanup_and_validate_program_arguments
	echo $BACKUP_DESCRIPTION
	echo && echo "###########" && echo

	########

	REGULAR_USER=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backup_schemes[] | select(.backup_type==$BACKUP_SCHEME_TYPE) | .regular_user')

	# cleanup_and_validate_program_arguments
	echo $REGULAR_USER
	echo && echo "###########" && echo

	########

	REGULAR_USER_HOME_DIR=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backup_schemes[] | select(.backup_type==$BACKUP_SCHEME_TYPE) | .regular_user_home_dir')

	# cleanup_and_validate_program_arguments
	echo $REGULAR_USER_HOME_DIR
	echo && echo "###########" && echo

	########

	LOG_FILE=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backup_schemes[] | select(.backup_type==$BACKUP_SCHEME_TYPE) | .log_file')

	# TODO: generalise cleanup_and_validate_program_arguments
	echo $LOG_FILE
	echo && echo "###########" && echo

	########



	
	#echo "ALL_THE_PARAMETERS_STRING: $ALL_THE_PARAMETERS_STRING"
	echo > "$LOG_FILE"
	echo "THIS_HOST: $THIS_HOST" >> "$LOG_FILE" # debug
	echo "ALL_THE_PARAMETERS_STRING: $ALL_THE_PARAMETERS_STRING" >> "$LOG_FILE" # debug
	echo "PROGRAM_PARAM_1: $PROGRAM_PARAM_1" >> "$LOG_FILE" # debug	
	#echo "program:" && echo "$0" && exit 0 # debug
	#output=$(dummy 2)
	#echo $output && exit 0 # debug
	echo $(whoami) >> "$LOG_FILE"
	echo $(pwd) >> "$LOG_FILE"
	echo "RUN_MODE: $RUN_MODE" >> "$LOG_FILE" # debug
	#exit 0 # debug



}

##############################################################################################

function program_requirements() 
{
  echo "Please install jq, and curl"
  exit 1
}

## check requirements
#for program_name in jq curl
#do
#  which $program_name >/dev/null 2>&1 || program_requirements
#done

###############################################################################################
# exit program with non-zero exit code
function exit_with_error()
{
	
	error_code="$1"
	error_message="$2"

	if [[ $RUN_MODE =~ "interactive" ]]
	then
		echo "EXIT CODE: $error_code"		
		echo "$error_message" && echo && sleep 1
		echo "USAGE: $(basename $0) [ABSOLUTE PATH TO CONFIGURATION FILE]?" && echo && sleep 1

	else
		echo "EXIT CODE: $error_code" >> "$LOG_FILE"
		echo "$error_message" >> "$LOG_FILE"	

	fi

	exit $error_code

}

###############################################################################################
function check_no_of_program_args()
{
	#echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	#echo "ACTUAL_NO: $ACTUAL_NO_OF_PROGRAM_PARAMETERS"
	
	# establish that number of parameters is valid
	if [[ $ACTUAL_NO_OF_PROGRAM_PARAMETERS -gt $MAX_EXPECTED_NO_OF_PROGRAM_PARAMETERS ]]
	then
		msg="Incorrect number of command line arguments. Exiting now..."
		exit_with_error "$E_INCORRECT_NUMBER_OF_ARGS" "$msg"
	fi
	

	#echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}

###############################################################################################
# this program is allowed to have ... arguments
function cleanup_and_validate_program_arguments()
{	
	# only the regular user can call using zero parameters as in an interactive shell
	# the root user is non-interactive, so must provide exactly one parameter

	if [ $ACTUAL_NO_OF_PROGRAM_PARAMETERS -eq 1 ]
	then			
		# sanitise_program_args
		sanitise_absolute_path_value "$PROGRAM_PARAM_1"
		#echo "test_line has the value: $test_line"
		PROGRAM_PARAM_TRIMMED=$test_line
		validate_program_args "$PROGRAM_PARAM_TRIMMED"			
			
	elif [ $ACTUAL_NO_OF_PROGRAM_PARAMETERS -eq 0 ] && [ $RUN_MODE == "batch" ]
	then
		msg="Incorrect number of command line arguments. Exiting now..."
		exit_with_error "$E_INCORRECT_NUMBER_OF_ARGS" "$msg"

	elif [ $ACTUAL_NO_OF_PROGRAM_PARAMETERS -eq 0 ] && [ $RUN_MODE == "interactive" ]
	then
		# this script was called by regular user, with zero parameters
		
		get_path_to_config_file # get path to the configuration file from user
	
	else
		# ...failsafe case
		msg="Incorrect number of command line arguments. Exiting now..."
		exit_with_error "$E_UNEXPECTED_BRANCH_ENTERED" "$msg"
	fi
	

}

###############################################################################################
# here because we're a logged in, regular user with interactive shell
# we're here to provide the absolute path to a backup configuration file
function get_path_to_config_file()
{
	echo "Looks like you forgot to add the configuration file as a program argument..." && echo && sleep 1

	echo "Please enter it now to continue using this program" && echo && sleep 1

	echo "Enter (copy-paste) the absolute path to the backup configuration file:" && echo

	#
	find /home -type f -name "*backup-configs.json" && echo 

	echo && echo
	read path_to_config_file

	if [ -n "$path_to_config_file" ] 
	then
		sanitise_absolute_path_value "$path_to_config_file"
		#echo "test_line has the value: $test_line"
		path_to_config_file=$test_line

		validate_program_args "$path_to_config_file"		

	else
		# 
		msg="The valid form test FAILED and returned: $return_code. Exiting now..."
		exit_with_error "$E_UNEXPECTED_ARG_VALUE" "$msg"
	fi
}
###############################################################################################
function validate_program_args()
{
	#echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	test_filepath="$1"

	# this valid form test works for sanitised file paths
	test_file_path_valid_form "$test_filepath"
	return_code=$?
	if [ $return_code -eq 0 ]
	then
		echo "The configuration filename is of VALID FORM"
	else
		msg="The valid form test FAILED and returned: $return_code. Exiting now..."
		exit_with_error "$E_UNEXPECTED_ARG_VALUE" "$msg"
	fi

	# if the above test returns ok, ...
	test_file_path_access "$test_filepath"
	return_code=$?
	if [ $return_code -eq 0 ]
	then
		#echo "The configuration file is ACCESSIBLE OK"
		CONFIG_FILE_FULLPATH="$test_filepath"

	else
		msg="The configuration filepath ACCESS TEST FAILED and returned: $return_code. Exiting now..."
		exit_with_error "$E_FILE_NOT_ACCESSIBLE" "$msg"
	fi


	#echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}


##########################################################################################################
# entry test to prevent running this program on an inappropriate host
function entry_test()
{
	go=36
	#echo "go was set to: $go"

	for authorised_host in ${AUTHORISED_HOST_LIST[@]}
	do
		#echo "$authorised_host"
		[ $authorised_host == $THIS_HOST ] && go=0 || go=1
		[ "$go" -eq 0 ] && echo "THE CURRENT HOST IS AUTHORISED TO USE THIS PROGRAM" && break
	done

	# if loop finished with go=1
	[ $go -eq 1 ] && echo "UNAUTHORISED HOST. ABOUT TO EXIT..." && sleep 2 && exit 1

	#echo "go was set to: $go"

}

###############################################################################################
# Display a program header:
function display_program_header(){

	echo
	echo -e "		\033[33m===================================================================\033[0m";
	echo -e "		\033[33m||   Welcome to the host-specific configuration file backuper    ||  author: adebayo10k\033[0m";  
	echo -e "		\033[33m===================================================================\033[0m";
	echo

	# REPORT SOME SCRIPT META-DATA
	echo "The absolute path to this script is:	$0"
	echo "Script root directory set to:		$(dirname $0)"
	echo "Script filename set to:			$(basename $0)" && echo

	echo -e "\033[33mREMEMBER TO RUN THIS PROGRAM ON EVERY HOST!\033[0m" && sleep 1 && echo
		
}

###############################################################################################
# give user option to leave if here in error:
function get_user_permission_to_proceed(){

	echo " Press ENTER to continue or type q to quit."
	echo && sleep 1

	# TODO: if the shell level is -ge 2, called from another script so bypass this exit option
	read last_chance
	case $last_chance in 
	[qQ])	echo
			echo "Goodbye!" && sleep 1
			exit 0
				;;
	*) 		echo "You're IN..." && echo && sleep 1
				;;
	esac 
}


##########################################################################################################
# keep sanitise functions separate and specialised, as we may add more to specific value types in future
# FINAL OPERATION ON VALUE, SO GLOBAL test_line SET HERE. RENAME CONCEPTUALLY DIFFERENT test_line NAMESAKES
function sanitise_absolute_path_value ##
{
	#echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	# sanitise values
	# - trim leading and trailing space characters
	# - trim trailing / for all paths
	test_line="${1}"
	#echo "test line on entering "${FUNCNAME[0]}" is: $test_line" && echo

	while [[ "$test_line" == *'/' ]] ||\
	 [[ "$test_line" == *[[:blank:]] ]] ||\
	 [[ "$test_line" == [[:blank:]]* ]]
	do 
		# TRIM TRAILING AND LEADING SPACES AND TABS
		# backstop code, as with leading spaces, config file line wouldn't even have been
		# recognised as a value!
		test_line=${test_line%%[[:blank:]]}
		test_line=${test_line##[[:blank:]]}

		# TRIM TRAILING / FOR ABSOLUTE PATHS:
		test_line=${test_line%'/'}
	done

	#echo "test line after trim cleanups in "${FUNCNAME[0]}" is: $test_line" && echo

	#echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo
}
##########################################################################################################
# basically a trim function that lets us prepare a relative path to be tagged onto an absolute one,
# but also trims ANY string argument passed in.
# GLOBAL test_line SET HERE...
function sanitise_trim_relative_path()
{
	#echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	# sanitise (well the trimming part anyway) values
	# - trim leading and trailing space characters
	# - trim leading / for relative paths
	# - trim trailing / for all paths

	test_line="${1}"
	#echo "test line on entering "${FUNCNAME[0]}" is: $test_line" && echo

	while [[ "$test_line" == *'/' ]] ||\
	 [[ "$test_line" == [[:blank:]]* ]] ||\
	 [[ "$test_line" == *[[:blank:]] ]]

	do 
		# TRIM TRAILING AND LEADING SPACES AND TABS
		test_line=${test_line%%[[:blank:]]}
		test_line=${test_line##[[:blank:]]}

		# TRIM TRAILING / FOR ABSOLUTE PATHS:
		test_line=${test_line%'/'}

	done

	# FINALLY, JUST THE ONCE, TRIM LEADING / FOR RELATIVE PATHS:
	# afer this, test_line should just be the directory name, 
	test_line=${test_line##'/'}

	#echo "test line after trim cleanups in "${FUNCNAME[0]}" is: $test_line"

	#echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo
}

##########################################################################################################
# firstly, we test that the parameter we got is of the correct form for an absolute file | sanitised directory path 
# if this test fails, there's no point doing anything further
# 
function test_file_path_valid_form
{
	#echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_file_fullpath=$1
	
	#echo "test_file_fullpath is set to: $test_file_fullpath"
	#echo "test_dir_fullpath is set to: $test_dir_fullpath"

	if [[ $test_file_fullpath =~ $ABS_FILEPATH_REGEX ]]
	then
		#echo "THE FORM OF THE INCOMING PARAMETER IS OF A VALID ABSOLUTE FILE PATH"
		test_result=0
	else
		echo "AN INCOMING PARAMETER WAS SET, BUT WAS NOT A MATCH FOR OUR KNOWN PATH FORM REGEX "$ABS_FILEPATH_REGEX"" && sleep 1 && echo
		echo "Returning with a non-zero test result..."
		test_result=1
		return $E_UNEXPECTED_ARG_VALUE
	fi 

	#echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}

###############################################################################################
# need to test for read access to file 
# 
function test_file_path_access
{
	#echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_file_fullpath=$1

	#echo "test_file_fullpath is set to: $test_file_fullpath"

	# test for expected file type (regular) and read permission
	if [ -f "$test_file_fullpath" ] && [ -r "$test_file_fullpath" ]
	then
		# test file found and ACCESSIBLE OK
		#echo "Test file found to be readable" && echo
		test_result=0
	else
		# -> return due to failure of any of the above tests:
		test_result=1 # just because...
		echo "Returning from function \"${FUNCNAME[0]}\" with test result code: $E_REQUIRED_FILE_NOT_FOUND"
		return $E_REQUIRED_FILE_NOT_FOUND
	fi

	#echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}

###############################################################################################
# generic need to test for access to a directory
# 
function test_dir_path_access
{
	#echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_dir_fullpath=$1

	#echo "test_dir_fullpath is set to: $test_dir_fullpath"

	if [ -d "$test_dir_fullpath" ] && cd "$test_dir_fullpath" 2>/dev/null
	then
		# directory file found and ACCESSIBLE
		#echo "directory "$test_dir_fullpath" found and ACCESSED OK" && echo
		test_result=0
	elif [ -d "$test_dir_fullpath" ] ## 
	then
		# directory file found BUT NOT accessible CAN'T RECOVER FROM THIS
		echo "directory "$test_dir_fullpath" found, BUT NOT ACCESSED OK" && echo
		test_result=1
		echo "Returning from function \"${FUNCNAME[0]}\" with test result code: $E_FILE_NOT_ACCESSIBLE"
		return $E_FILE_NOT_ACCESSIBLE
	else
		# -> directory not found: THIS CAN BE RESOLVED BY CREATING THE DIRECTORY
		test_result=1
		echo "Returning from function \"${FUNCNAME[0]}\" with test result code: $E_REQUIRED_FILE_NOT_FOUND"
		return $E_REQUIRED_FILE_NOT_FOUND
	fi

	#echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}

##########################################################################################################
# declare after param validation, as list depends on knowing users' home dir etc...
function setup_src_dirs()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	# get crontab -l outputs redirected into a file that we can backup
	if [ $USER_PRIV == "reg" ]
	then
		echo "$(sudo crontab -l 2>/dev/null)" > "${my_homedir}/temp_root_cronfile"
		echo "$(crontab -l 2>/dev/null)" > "${my_homedir}/temp_user_cronfile"
	else
		# if non-interactive root shell
		echo "$(crontab -l 2>/dev/null)" > "${my_homedir}/temp_root_cronfile"
		echo "$(crontab -u ${my_username} -l 2>/dev/null)" > "${my_homedir}/temp_user_cronfile"
	fi


	# declare sources list here UNTIL JSON CONFIGURATION
	hostfiles_fullpaths_list=(
	# host-specific dirs
	"${my_homedir}/research"
	"${my_homedir}/secure"
	"${my_homedir}/Downloads"
	# global configs
	"/etc"
	"/var/www"
	"/var/log/syslog"
	"${my_homedir}/.ssh/config"
	"${my_homedir}/.config"
	"/usr/lib/node_modules/npm/package.json"
	"/usr/lib/node_modules/eslint/package.json"
	# vscode workspace configs...
	"${my_homedir}/Documents/businesses/tech_business/workspaces"
	"${my_homedir}/bin/workspaces"
	"${my_homedir}/Code/workspaces"
	# git managed source code AND configs...
	"${my_homedir}/bin/utils"
	"${my_homedir}/Documents/businesses/tech_business/coderDojo/coderdojo-projects"
	"${my_homedir}/Documents/businesses/tech_business/adebayo10k.github.io"
	"${my_homedir}/Documents/businesses/tech_business/CodingActivityPathChooser"
	"${my_homedir}/.gitconfig"
	#"/cronjob configs..."
	"${my_homedir}/temp_root_cronfile"
	"${my_homedir}/temp_user_cronfile"
	)
	
	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo
	
	
}

##########################################################################################################
# establish whether we're able to backup our src files to, in order of preference:
#	$DST_BACKUP_DIR_EXTERNAL, $DST_BACKUP_DIR_LOCAL
function setup_dst_dirs()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	setup_outcome=42 #initialise to fail state (!= 0)

	# establish whether external drive/network fs/remote fs is mounted

	for dst_dir in "$DST_BACKUP_DIR_EXTERNAL" "$DST_BACKUP_DIR_LOCAL"
	do
		echo "TRYING dst dir: $dst_dir"

		# test dst_dir exists and accessible
		test_dir_path_access "$dst_dir"
		return_code=$?
		if [ $return_code -eq 0 ]
		then
			# dst_dir found and accessible ok
			echo "The dst_dir filepath EXISTS and WORKS OK" && echo
			dst_dir_current_fullpath="$dst_dir"
			setup_outcome=0 #success
			break

		elif [ $return_code -eq $E_REQUIRED_FILE_NOT_FOUND ]
		then
			# dst_dir did not exist
			echo "The dst HOLDING (PARENT) DIRECTORY WAS NOT FOUND. test returned: $return_code"
			
			mkdir "$dst_dir" >/dev/null >&1 && echo "Creating the directory now..." && echo && \
			dst_dir_current_fullpath="$dst_dir" && setup_outcome=0 && break \
			|| setup_outcome=1 && echo "Directory creation failed for:" && echo "$dst_dir" && echo && continue			

		else
			# dst_dir found but not accessible
			msg="The dst DIRECTORY filepath ACCESS TEST FAILED and returned: $return_code. Exiting now..."
			exit_with_error "$E_FILE_NOT_ACCESSIBLE" "$msg"
		fi

	done

	if [ "$setup_outcome" -ne 0 ]
	then
		# couldn't mkdirs, no dirs to make or just something not good...
		msg="Unexpected, UNKNOWN ERROR setting up the dst dir... Exiting now..."
		exit_with_error "$E_UNKNOWN_ERROR" "$msg"
	fi
			
	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}

############################################################################################
# called for each directory in the list
function traverse() {
	date_label=$(date +'%F')
	
	for file in "$1"/*
	do
	    # sanitise copy of file to make it ready for appending as a regular file
		sanitise_trim_relative_path "${file}"
		#echo "test_line has the value: $test_line"
		rel_filepath=$test_line

		# happens for the first only (TODO: test this with a debug echo!)
		mkdir -p "$(dirname "${dst_dir_current_fullpath}/${rel_filepath}")"
		
		# how does the order of these tests affect performance?
		if  [ -f "${file}" ]  && [ ! -h "${file}" ] && [ $USER_PRIV == "reg" ]; then
			# preserve file metadata, never follow symlinks, update copy if necessary
			# give some user progress feedback
			#echo "Copying file $file ..."
			sudo cp -uvPp "${file}" "${dst_dir_current_fullpath}/${rel_filepath}"

		elif [ -f "${file}" ] && [ ! -h "${file}" ] && [ $USER_PRIV == "root" ]; then
			#echo "Copying file $file ..."
			cp -uvPp "${file}" "${dst_dir_current_fullpath}/${rel_filepath}"

		# if  file is a symlink, reject (irrespective of USER_PRIV)
		elif [ -h "${file}" ]; then
			echo "Skipping symlink file: $file ..."
			continue 

	    elif [ -d "${file}" ]; then # file must be a directory to have arrived here, but check anyway.
			# skip over excluded subdirectories
			# TODO: exlude .git dirs completely. after all, this is a git-independent backup!
			if  [ -z "$(ls -A $file)" ] || [[ $file =~ '.config/Code' ]] # || [[ $file =~ '.git/objects' ]] 
			then
				echo "Skipping excluded dir: $file"
				continue
			fi
			# enter recursion with a non-empty directory
	        echo "entering recursion with: ${file}"
	        traverse "${file}"
		else
			# failsafe condition
			echo "FAILSAFE BRANCH ENTERED!! WE SHOULD NOT BE HERE!!"
			echo "WEIRD FILE EXISTS on this host for:"
			echo $file && echo
	    fi
	done
}

###############################################################################################
function backup_regulars_and_dirs()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	# 
	if [ $RUN_MODE == "interactive" ]
	then
		echo "Now is a good time to tidy up the ~/Downloads directory. I'll wait here." && echo
		echo "Press ENTER when ready to continue..." && read
	fi

	#setup_src_dirs	# later, this may be from json config
	
	date_label=$(date +'%F')

	# copy sparse sources into dst
	for file in ${hostfiles_fullpaths_list[@]}
	do
		# sanitise file to make it ready for appending
		sanitise_trim_relative_path "${file}"
		#echo "test_line has the value: $test_line"
		rel_filepath=$test_line

		# happens for the first only (TODO: test this with a debug echo!)
		mkdir -p "$(dirname "${dst_dir_current_fullpath}/${rel_filepath}")"

		# if source directory is not empty...
		if [ -d $file ] && [ -n "$(ls -A $file)" ]
		then
			## give user some progress feedback
			echo "Copying dir $file ..." && traverse $file
		elif [ -f $file ] && [ $USER_PRIV == "reg" ] && [ ! -h "${file}" ]
		then
			# give some user progress feedback
			echo "Copying top level file $file ..."
			# preserve file metadata, never follow symlinks, update copy if necessary
			sudo cp -uvPp $file "${dst_dir_current_fullpath}/${rel_filepath}"
		elif [ -f $file ] && [ $USER_PRIV == "root" ] && [ ! -h "${file}" ]
		then
			# give some user progress feedback
			echo "Copying top level file $file ..."
			cp -uvPp $file "${dst_dir_current_fullpath}/${rel_filepath}"
		elif  [ -h "${file}" ]
		then
			echo "Skipping symbolic link in configuration list..."
			continue
		else
			# failsafe
			echo "Entered the failsafe"
			echo "WEIRD, NO SUCH FILE EXISTS on this host for:"
			echo $file && echo
		fi

	done

	# delete those temporary crontab -l output files
	rm -fv "${my_homedir}/temp_root_cronfile" "${my_homedir}/temp_user_cronfile"
	
	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}

###############################################################################################
# chown (but not chmod) privilege level of all backup dir contents.
# why? reg user doesn't need to access them, and we've got sudo tar if needed.
# preserving ownership etc. might also have more fidelity, and enable any restore operations.
function change_file_ownerships()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	# USER_PRIV (reg or root) branching:
	if [ $USER_PRIV == "reg" ]
	then
		sudo chown -R ${my_username}:${my_username} "${dst_dir_current_fullpath}"
	else
		chown -R ${my_username}:${my_username} "${dst_dir_current_fullpath}"
	fi	
	
	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo
}

###############################################################################################
# if we have an interactive shell, give user a summary of dir sizes in the dst dir
function report_summary()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	for file in "${dst_dir_current_fullpath}"/*
	do
		if [ -d $file ]
		then
			# assuming we're still giving ownership to reg user, else need sudo
			du -h --summarize "$file"
		fi
	done


	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}

###############################################################################################
function dummy()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	n=$1
	echo "data $(($n*6)) ssh:5490"


	#echo -e "\e[32msetup variables\e[0m"
	#echo -e "\e[32m\$cp template-script.sh new-script.sh\e[0m"
	#echo -e "\033[33mREMEMBER TO .... oh crap!\033[0m" && sleep 4 && echo
#

	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}

###############################################################################################


main "$@"; exit
