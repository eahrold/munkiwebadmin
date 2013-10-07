#!/bin/bash

#set -xv
export PATH="$PATH:/usr/local/bin:/usr/local/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"

PROJECT_NAME='munkiwebadmin'
PROJECT_SETTINGS_DIR=""
EXAMPLE_SETTINGS_FILE="settings_template.py"

GIT_REPO="https://github.com/eahrold/munkiwebadmin.git"
USER_NAME='munkiwebadmin'
GROUP_NAME='munki'
APACHE_SUBPATH='munkiwebadmin'

OSX_CONF_FILE_DIR="OSX"
OSX_WEBAPP_PLIST='com.google.code.munkiwebadmin.plist'
APACHE_CONFIG_FILE='httpd_munkiwebadmin.conf'
WSGI_FILE='munkiwebadmin.wsgi'

VIRENV_NAME='munkiwebadmin_env'
PIP_REQUIREMENTS="setup/requirements.txt"
OSX_SERVER_WSGI_DIR="/Library/Server/Web/Data/WebApps/"
OSX_SERVER_APACHE_DIR="/Library/Server/Web/Config/apache2/"
OSX_SERVER_SITES_DEFAULT="/Library/Server/Web/Data/Sites/"

pre_condition_test(){
	[[ -z $(which git) ]] && cecho alert "you must first install git. you can download it from Apple." && exit 1
	
	if [[ $EUID != 0 ]]; then
		cecho red "This script needs to run with elevated privlidges, enter your password"
	    sudo "$0" "$@"
	    exit 1
	fi
}

make_user_and_group(){
	cecho bold "Checking user and group..."
	local USER_EXISTS=$(dscl . list /Users | grep -c "${USER_NAME}")
	local GROUP_EXISTS=$(dscl . list /Groups | grep -c "${GROUP_NAME}")
	
	
	if [ $USER_EXISTS -eq 0 ]; then
		cecho bold "Creating user ${USER_NAME}..."
		
		USER_ID=$(check_ID Users UniqueID)
		dscl . create /Users/"${USER_NAME}"
		dscl . create /Users/"${USER_NAME}" passwd *
		dscl . create /Users/"${USER_NAME}" UniqueID "${USER_ID}"
	else
		cecho bold "User ${GROUP_NAME} already exists, skipping..."
	fi

	
	if [ $GROUP_EXISTS -eq 0 ]; then
		cecho bold "Creating user ${USER_NAME}..."
		GROUP_ID=$(check_ID Groups PrimaryGroupID)
		dseditgroup -o create -i "${GROUP_ID}" -n . "${GROUP_NAME}"
	else
		cecho bold "Group ${GROUP_NAME} already exists, skipping..."
		GROUP_ID=$(dscl . read /Groups/"${GROUP_NAME}" PrimaryGroupID)
	fi
	
	### this is outside of the conditional statement 
	### to correct any previously set GroupID
	dscl . create /Users/"${USER_NAME}" PrimaryGroupID "${GROUP_ID}"
}

check_ID(){
	# $1 is the dscl path and $2 is the Match
	local ID=$(/usr/bin/dscl . list /$1 $2 | awk '{print $2}'| grep '[4][0-9][0-9]'| sort| tail -1)
	[[ -n $ID ]] && ((ID++)) || ID=400
	
	local __rc=false
	while [ $__rc == false ]; do
		local IDCK=$(/usr/bin/dscl . list /$1 $2 | awk '{print $2}'| grep -c ${ID})
		if [ $IDCK -eq 0 ]; then
			__rc=true
		else
			cecho alert "That %2 is in use"
			read -e -p "Please specify another (press c to cancel autoinstll script):" ID
		fi
	done
	
	if [ "${ID}" == "c" ] ; then
		cecho alert "exiting script."
		exit 1
	fi
	echo $ID
	 
}

install(){
	local VEV=$(which virtualenv)
	[[ -z "${VEV}" ]] && easy_install virtualenv
	"${VEV}" "${VIR_ENV}"
			
	cd "${VIR_ENV}"
	
	if [ ! -d "${VIR_ENV}/${PROJECT_NAME}" ]; then
		 git clone "${GIT_REPO}" ./"${PROJECT_NAME}"
	 else
		 cd "${PROJECT_NAME}"
		 git pull
		 cd ..
	 fi
	
	source bin/activate
	pip install -r ./"${PROJECT_NAME}/${PIP_REQUIREMENTS}"
	cd "${PROJECT_NAME}"
	
	configure
}

configure(){
	if [ "${PROJECT_SETTINGS_DIR}" != "" ]; then
		eval_dir PROJECT_SETTINGS_DIR
	fi
		
	cp "${PROJECT_SETTINGS_DIR}${EXAMPLE_SETTINGS_FILE}" "${PROJECT_SETTINGS_DIR}settings.py"
	local SETTINGS_FILE="${PROJECT_SETTINGS_DIR}settings.py"
	
	
	cecho purple "Now we'll do some basic configuring to the settings.py file"
	cread question "Where is your munki repo? " MUNKI_REPO
	
	local __rc=false
	while [ $__rc == false ]; do
	if [ -d ${MUNKI_REPO} ];then
		ised "MUNKI_REPO_DIR" "MUNKI_REPO_DIR = '${MUNKI_REPO}'" "${SETTINGS_FILE}"
		__rc=true
	else
		cecho alert "there isn't anything at that path"
		cread alert "are you sure you want to use that (y/n)?" yesno
		if [[ $REPLY =~ ^[Yy]$ ]];then
			ised "MUNKI_REPO_DIR" "MUNKI_REPO_DIR = '${MUNKI_REPO}'" "${SETTINGS_FILE}"
			__rc=true
		fi
	fi
	done
	
	cread question "Do you want to run on subpath ${APACHE_SUBPATH}? " yesno
	if [[ $REPLY =~ ^[Yy]$ ]];then
		ised "RUN_ON_SUBPATH =" "RUN_ON_SUBPATH = ${APACHE_SUBPATH}" "${SETTINGS_FILE}"	
	fi
	
	cread question "Run in DEBUG mode [y/n]? " yesno
	if [[ $REPLY =~ ^[Yy]$ ]];then
		ised "DEBUG =" "DEBUG = True" "${SETTINGS_FILE}"
	fi
	
	cread question "Allow All Hosts [y/n)]? " yesno
	if [[ $REPLY =~ ^[Yy]$ ]];then
		ised "ALLOWED_HOSTS =" "ALLOWED_HOSTS = ['*']" "${SETTINGS_FILE}"
	fi
	
	python manage.py collectstatic
	python manage.py syncdb
	
	set_permissions
	
	if [ ${OSX_SERVER_INSTALL} == true ];then
		ised "RUNNING_ON_APACHE=" "RUNNING_ON_APACHE=True" "${SETTINGS_FILE}"
		install_osx_server_components
	else
		cread question "Do you Want to start the django test server now [Y(es)/N(o)]?" yesno
		if [[ $REPLY =~ ^[Yy]$ ]];then
			python manage.py runserver
		fi
	fi
}

install_osx_server_components(){
	[[ ! -d "${OSX_SERVER_APACHE_DIR}/webapps/" ]] && mkdir -p "${OSX_SERVER_APACHE_DIR}/webapps/"
	cp -p "${VIR_ENV}/${PROJECT_NAME}/${OSX_CONF_FILE_DIR}/${OSX_WEBAPP_PLIST}" "${OSX_SERVER_APACHE_DIR}/webapps/"	
	
	## configure the .conf file
	
	local alias_str="Alias /static_${PROJECT_NAME}/ ${VIR_ENV}${PROJECT_NAME}/${PROJECT_SETTINGS_DIR}/static/"
	local daemonprocess_str="WSGIDaemonProcess ${USER_NAME} user=${USER_NAME} group=${GROUP_NAME}"
	local processgroup_str="WSGIProcessGroup ${GROUP_NAME}"
	
	if [ ${USER_NAME} == "www" ]; then
		local wsgiscript_str="WSGIScriptAlias /${APACHE_SUBPATH} /Library/Server/Web/Data/WebApps/${PROJECT_NAME}.wsgi"
		echo "${alias_str}" > "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
		echo "${wsgiscript_str}" >> "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
	else
		cp -p "${VIR_ENV}/${PROJECT_NAME}/${OSX_CONF_FILE_DIR}/${APACHE_CONFIG_FILE}" "${OSX_SERVER_APACHE_DIR}/"
		
		ised "Alias" "${alias_str}" "${OSX_SERVER_APACHE_DIR}${APACHE_CONFIG_FILE}"
		ised "WSGIDaemonProcess" "${daemonprocess_str}" "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
		ised "WSGIProcessGroup" "${processgroup_str}" "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
	fi
	
	
	
	## copy and configure the .wsgi file
	[[ ! -d "${OSX_SERVER_WSGI_DIR}/" ]] && mkdir -p "${OSX_SERVER_WSGI_DIR}/"	
	cp -p "${VIR_ENV}/${PROJECT_NAME}/${OSX_CONF_FILE_DIR}/${WSGI_FILE}" "${OSX_SERVER_WSGI_DIR}/"
	local venv_str="VIR_ENV_DIR = \'${VIR_ENV}\'"
	ised "VIR_ENV_DIR" "${venv_str}" "${OSX_SERVER_WSGI_DIR}/${WSGI_FILE}"
	
	cecho alert "You're Ready to go.  "
	cecho purple "Open Server.app, select the site, go to Advanced and enable the webapp."
}

set_permissions(){
	chown -R "${USER_NAME}":"${GROUP_NAME}" "${VIR_ENV}"
}

cecho(){	
	case "$1" in
		red|alert) local COLOR=$(printf "\\e[1;31m");;
		green|attention) local COLOR=$(printf "\\e[1;32m");;
		yellow|warn) local COLOR=$(printf "\\e[1;33m");;
		blue|question) local COLOR=$(printf "\\e[1;34m");;
		purple|info) local COLOR=$(printf "\\e[1;35m");;
		cyan|notice) local COLOR=$(printf "\\e[1;36m");;
		bold|prompt) local COLOR=$(printf "\\e[1;30m");;
		*) local COLOR=$(printf "\\e[0;30m");;
	esac
	
	if [ -z "${2}" ];then
		local MESSAGE="${1}"
	else
		local MESSAGE="${2}"
	fi

	local RESET=$(printf "\\e[0m")	
	echo "${COLOR}${MESSAGE}${RESET} ${3}"	
}


cread(){	
	case "$1" in
		red|alert) local COLOR=$(printf "\\e[1;31m");;
		green|attention) local COLOR=$(printf "\\e[1;32m");;
		yellow|warn) local COLOR=$(printf "\\e[1;33m");;
		blue|question) local COLOR=$(printf "\\e[1;34m");;
		purple|info) local COLOR=$(printf "\\e[1;35m");;
		cyan|notice) local COLOR=$(printf "\\e[1;36m");;
		bold|prompt) local COLOR=$(printf "\\e[1;30m");;
		*) local COLOR=$(printf "\\e[0;30m");;
	esac	
	local MESSAGE="${2}"
	local RESET=$(printf "\\e[0m")	
	if [ -z ${3} ];then
		read -e -p "${COLOR}${MESSAGE}${RESET} "
	elif [ ${3} == "yesno" ]; then
		read -e -p "${COLOR}${MESSAGE}${RESET} " -n 1 -r
	else
		read -e -p "${COLOR}${MESSAGE}${RESET} " VAR
		eval $3="'$VAR'"
	fi
}

eval_dir(){	 
# pass the name of the variable you want to eval
# so you would pass MYVAR rather than $MYVAR
	
	eval local __myvar=${!1} 2>/dev/null
	if [ $? == 0 ]; then
			
		local __len=${#__myvar}-1
		if [ "${__myvar:__len}" != "/" ]; then
		  __myvar=$__myvar"/"
		fi
		eval $1="'$__myvar'"
	else
		return 1
	fi
}


ised(){
	sed -i "" -e "s;^${1}.*;${2};" "${3}"
}

__main__(){
	pre_condition_test
	clear
	local __rc=false
	while [ $__rc == false ]; do
	cecho alert "You are about to run the $PROJECT_NAME installer"
	cecho alert "There's a few things to get out of the way"
	cecho question "First we need to determine what user should own the webapp process" 
	cecho purple "1) create a new user and group" "(recommended)"
	cecho purple "2) yourself" "(fine for testing)"
	cecho purple "3) the www user" "(if you're running on both http and https)" 
		read -e -p "Please Choose: " -n 1 -r
		if [[ $REPLY -eq 1 ]];then
			make_user_and_group
			if [ $? == 0 ]; then
				__rc=true
			else
				cecho alert "There was a problem creating the user, chose an alternate option (1 or 3)"
			fi
		elif [[ $REPLY -eq 2 ]];then
			USER_NAME=$(who | grep console | head -1 |awk '{print $1}')
			GROUP_NAME=$(dscl . read /Users/${USER_NAME} PrimaryGroupID|awk '{print $2}')
			__rc=true	
		elif [[ $REPLY -eq 3 ]];then
			USER_NAME='www'
			GROUP_NAME='www'
			__rc=true
		fi
	done
	
	
	if [ -d "/Applications/Server.app" ]; then
		cread question "will you be running on OS X Server [y/n]?" yesno
		if [[ $REPLY =~ ^[Yy]$ ]];then
			OSX_SERVER_INSTALL=true
		fi 
	fi
	
	__rc=false
	while [ $__rc == false  ]; do
		cecho question "Where Would you like to install the Virtual Environment?"
		
		if [ "${OSX_SERVER_INSTALL}" == true ]; then
			cecho question "(Leave Blank to set as ${OSX_SERVER_SITES_DEFAULT})"
 			cread question "Path:" T_VIR_ENV
			if [ ! -z "${T_VIR_ENV}" ]; then
				VIR_ENV="${T_VIR_ENV}"
			else
				VIR_ENV="${OSX_SERVER_SITES_DEFAULT}"
			fi
		else
			cread question "Path:" VIR_ENV
		fi
		
		#This will make sure there's a trailing slash on the path
		eval_dir VIR_ENV
		
		if [ $? == 0 ]; then
			if [ -d  "${VIR_ENV}" ]; then
				VIR_ENV="${VIR_ENV}${VIRENV_NAME}"
				eval_dir VIR_ENV	
				cecho purple "We will create this env: " "${VIR_ENV}"
				cread question "Is this Correct (y/n/c)]? " yesno
				if [[ $REPLY =~ ^[Yy]$ ]];then
				    __rc=true
				elif [[ $REPLY =~ ^[Cc]$ ]];then
					cecho bold "Canceling..."
					exit 1
				fi 
			else
				cecho alert "That's not a valad path, please try again"
			fi
		else
			cecho alert "Please choose a POSIX Compatable Path (i.e no spaces!)"
		fi
	done
	install
}

__main__

exit 0