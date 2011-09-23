#!/bin/bash

# This scripts expects the following in /var/aegir
#   /basefiles
#   /basefiles/miruku_features
#   /basefiles/miruku_features/miruku_wysiwyg_img_basic
#   /basefiles/miruku_project_base
#   /makefiles/
#   /projects
#   /scripts


#logfile=logs/miruku_$1.log
#exec > $logfile 2>&1

### Bashtrap for cleaning up after ctrl-c

trap bashtrap INT

bashtrap() {
	if [ "$MIRUKU_PROV" = "stage1_begin" ];then
		exit
	elif [ "$MIRUKU_PROV" = "stage2_makethings" ];then
		if [ "$SCRIPT_TASK" = "a" ]; then rm -rf $PROJECT_DIR ; fi
		echo
		exit
	elif [ "$MIRUKU_PROV" = "stage3_aegirthings_platform_files" ];then
		if [ "$SCRIPT_TASK" = "a" ]; then rm -rf $PROJECT_DIR ; fi
		rm -rf $PROJECT_PLATFORM
		echo
		exit
	elif [ "$MIRUKU_PROV" = "stage4_aegirthings_platform_filesdrush" ];then
		# Removes Drush platform alias
		drush provision-save "@platform_$PROJECT_NAME" --root="$PROJECT_PLATFORM" --delete
		drush @hostmaster hosting-dispatch
		
		if [ "$SCRIPT_TASK" = "a" ]; then rm -rf $PROJECT_DIR ; fi
		rm -rf $PROJECT_PLATFORM
		echo
		exit
	elif [ "$MIRUKU_PROV" = "stage5_aegirthings_platform_filesdrushsite" ];then
		# Removes site files, db and vhost
		drush "@$PROJECT_DOMAIN" provision-delete 
		# Removes Drush site alias
		drush provision-save --root="$PROJECT_PLATFORM" "@$PROJECT_DOMAIN" --delete
		
		# Removes Drush platform alias
		drush provision-save "@platform_$PROJECT_NAME" --root="$PROJECT_PLATFORM" --delete
		drush @hostmaster hosting-dispatch

		rm -rf $PROJECT_DIR
		rm -rf $PROJECT_PLATFORM
		echo
		exit
	fi
}

### Check user is aegir

dependencies() {
	if [ `whoami` != "aegir" ] ; then
		echo "This script should be ran as the aegir user."
		exit 1
	fi
}

# Set options from command line input

getoptions() {
	while getopts ":p:a:d:o:" opt; do
		case $opt in
			p)
				PROJECT_NAME="$OPTARG"
				;;
			a)
				PROJECT_DOMAIN="$OPTARG"
				;;
			d)
				DRUPAL_VERSION="$OPTARG"
				;;
			o)
				SCRIPT_TASK="$OPTARG"
				;;
		esac
	done
	
	if [ ! "$PROJECT_NAME" ] || [ ! "$PROJECT_DOMAIN" ] || [ ! "$SCRIPT_TASK" ] ; then
		echo "**********************************"
		echo "*** Milk's Aeigr provision script"
		echo "*** Missing argument(s)"
		echo "*** -p projectname"
		echo "*** -a project.domain"
		echo "*** -d 6 / 7 (drupal version)"
		echo "*** -o a (create and provision)"
		echo "*** -o b (just provision)"
		echo "*** Cool?"
		echo "**********************************"
		exit
	fi

	echo
	echo "**********************************"
	echo "*** Milk's Aeigr provision script"
	echo "*** Project: $PROJECT_NAME"
	echo "*** Domain: $PROJECT_DOMAIN"
	echo -n "*** Task: "
	if [ "$SCRIPT_TASK" = "a" ]; then echo "create and provision"
	elif [ "$SCRIPT_TASK" = "b" ]; then echo "just provision"; fi	
	echo "*** Drupal: $DRUPAL_VERSION"
	echo "**********************************"	
}




### Set some variables

setvariables() {
	# Script stage counter
	MIRUKU_PROV=stage1_begin
	
	# The Aegir dir
	AEGIR_HOME=$HOME
	
	# Project folder for .make and .profile
	PROJECT_DIR=$AEGIR_HOME/projects/$PROJECT_NAME
	
	if [ "$DRUPAL_VERSION" = "6" ]; then THEME_NAME="terrain" ; fi
	if [ "$DRUPAL_VERSION" = "7" ]; then THEME_NAME="squaregrid" ; fi
	
	# Theme git folder
	THEME_GIT=$PROJECT_DIR/theme.git
	
	# Subtheme folder
	THEME_SUB=$PROJECT_DIR/theme.git/$PROJECT_NAME
	
	# Project config folder
	CONFIG_GIT=$PROJECT_DIR/config.git
	
	# Make file
	PROJECT_MAKE=$PROJECT_DIR/config.git/miruku_d$DRUPAL_VERSION\_$PROJECT_NAME.make
	
	# Config: Info file
	PROJECT_INFO=$PROJECT_DIR/config.git/miruku_d$DRUPAL_VERSION\_$PROJECT_NAME.info
	
	# Config: Profile file
	PROJECT_PROFILE=$PROJECT_DIR/config.git/miruku_d$DRUPAL_VERSION\_$PROJECT_NAME.profile

	# Config: Profile short
	PROFILE_SHORT=miruku_d$DRUPAL_VERSION\_$PROJECT_NAME

	# Project platform folder
	PROJECT_PLATFORM=$AEGIR_HOME/platforms/$PROJECT_NAME
}


makethings() {
	# Script stage counter
	MIRUKU_PROV=stage2_makethings
	
	# Create project folder
	mkdir $PROJECT_DIR
	mkdir $THEME_GIT
	mkdir $THEME_SUB
	mkdir $CONFIG_GIT
	
	# Clone base theme to new repo
	cd $THEME_GIT
	
	if [ "$DRUPAL_VERSION" = "6" ]; then
		git clone http://git.drupal.org/project/terrain.git
		cd terrain
		rm -rf .git/
		
		# Setup subtheme
		cd $THEME_SUB
		echo "; Terrain subtheme" > $PROJECT_NAME.info
		echo "" >> $PROJECT_NAME.info
		echo "name = $PROJECT_NAME" >> $PROJECT_NAME.info
		echo "description = Terrain subtheme for $PROJECT_NAME" >> $PROJECT_NAME.info
		echo "core = 6.x" >> $PROJECT_NAME.info
		echo "engine = phptemplate" >> $PROJECT_NAME.info
		echo "base theme = terrain" >> $PROJECT_NAME.info

	fi
	
	if [ "$DRUPAL_VERSION" = "7" ]; then
		git clone --branch 7.x-2.x http://git.drupal.org/project/squaregrid.git
		cd squaregrid
		rm -rf .git/
		
		# Setup subtheme
		cd $THEME_SUB
		echo "; Squaregrid subtheme" > $PROJECT_NAME.info
		echo "" >> $PROJECT_NAME.info
		echo "name = $PROJECT_NAME" >> $PROJECT_NAME.info
		echo "description = Squaregrid subtheme for $PROJECT_NAME" >> $PROJECT_NAME.info
		echo "core = 7.x" >> $PROJECT_NAME.info
		echo "engine = phptemplate" >> $PROJECT_NAME.info
		echo "base theme = squaregrid" >> $PROJECT_NAME.info	
		
		cp ../squaregrid/template.php template.php
	fi

	# Ask to manually edit the theme before comitting
	echo
	echo "*** Please edit theme if so required"
	read -p "*** Press return to continue"
	echo ""
	
	# Add and commit initial changes to theme Git repo
	cd $THEME_GIT
	git init
	git add --all
	echo
	git commit -m "Initial commit for $PROJECT_NAME theme"
	
	
	### Project .make
	
	# Git clone project theme from miruku base
	cd $PROJECT_DIR
	
	# Move files for new project 
	if [ "$DRUPAL_VERSION" = "6" ]; then
		git clone -l --no-hardlinks /var/aegir/basefiles/miruku_d6_base $CONFIG_GIT
		#shopt -s dotglob
		#mv ./tmp/* .
		#shopt -u dotglob
		#rm -rf ./tmp
		cd $CONFIG_GIT
		mv miruku_d6_base.make $PROJECT_MAKE
		mv miruku_d6_base.profile $PROJECT_PROFILE
		mv miruku_d6_base.info $PROJECT_INFO
	fi

	if [ "$DRUPAL_VERSION" = "7" ]; then
		git clone -l --no-hardlinks /var/aegir/basefiles/miruku_d7_base $CONFIG_GIT
		#shopt -s dotglob
		#mv ./tmp/* .
		#shopt -u dotglob
		#rm -rf ./tmp
		cd $CONFIG_GIT
		mv miruku_d7_base.make $PROJECT_MAKE
		mv miruku_d7_base.profile $PROJECT_PROFILE
		mv miruku_d7_base.info $PROJECT_INFO
	fi
	
	# Edit .make theme project name
	eval "sed -i s#miruku_theme#miruku_theme_$PROJECT_NAME#g $PROJECT_MAKE"
	
	# Edit .make theme project git path
	eval "sed -i s#theme_git_location#$THEME_GIT# $PROJECT_MAKE"
	
	# Edit .make to pull profile and info in project platform
	eval "sed -i s#profile_git_location#$CONFIG_GIT# $PROJECT_MAKE"
	eval "sed -i s#miruku_profile_base#$PROFILE_SHORT#g $PROJECT_MAKE"
	
	# Edit .info for Profile settings
	eval "sed -i s#Base#$PROJECT_NAME#g $PROJECT_INFO"
	eval "sed -i s/squaregrid/$PROJECT_NAME/g $PROJECT_INFO"
	
	# Edit .profile name argument
	eval "sed -i s/yourprofile/$PROFILE_SHORT/ $PROJECT_PROFILE"
	
	# Edit .gitignore for altered theme name and 
	# eval "sed -i s#miruku_base.make#miruku_d$DRUPAL_VERSION\_$PROJECT_NAME.make# .gitignore"
	
	# Ask if any changes need to be made to the .make
	echo
	echo "*** Please edit project .make and .info if so required"
	read -p "*** Press return to continue"
	echo
	
	# Remove renamed files from Git repo
	git ls-files --deleted | xargs git rm
	
	# Add all files in folder respecting .gitignore, so not using --all
	git add .
	
	# Make the commit
	git commit -m "First commit for $PROJECT_NAME"
	echo
}

### Create and Aegerise site

aegirthings() {
	echo "* Start doing Drush things now..."
	echo
	
	# Set the queue to run every 1 second, so we can force the dispatch command
	drush -y @hostmaster vset hosting_queue_tasks_frequency 1
	echo
	
	# Build platform with Drush Make
	echo "drush make --working-copy $PROJECT_MAKE $PROJECT_PLATFORM"
	MIRUKU_PROV=stage3_aegirthings_platform_files
	drush make --working-copy $PROJECT_MAKE $PROJECT_PLATFORM
	echo
	
	# Set an Aegir context for that platform
	echo "drush provision-save '@platform_$PROJECT_NAME' --root='$PROJECT_PLATFORM' --context_type='platform'"
	MIRUKU_PROV=stage4_aegirthings_platform_filesdrush
	drush provision-save "@platform_$PROJECT_NAME" --root="$PROJECT_PLATFORM" --context_type="platform"
	drush @hostmaster hosting-dispatch
	echo
	
	# Import that platform into hostmaster, the Aegir frontend
	echo "drush @hostmaster hosting-import '@platform_$PROJECT_NAME'"
	drush @hostmaster hosting-import "@platform_$PROJECT_NAME"
	drush @hostmaster hosting-dispatch
	echo
	
	# Set a site context in Aegir using the new platform and profile
	echo "drush provision-save '@$PROJECT_DOMAIN' --uri='$PROJECT_DOMAIN' --context_type='site' --platform='@platform_$PROJECT_NAME' --profile='miruku_$PROJECT_NAME' --db_server=@server_master --debug"
	MIRUKU_PROV=stage5_aegirthings_platform_filesdrushsite

        drush --uri="$PROJECT_DOMAIN" provision-save "@$PROJECT_DOMAIN" --context_type='site' --platform="@platform_$PROJECT_NAME" --profile="$PROFILE_SHORT"
#	drush provision-save "@$PROJECT_DOMAIN" --uri="$PROJECT_DOMAIN" --context_type='site' --platform="@platform_$PROJECT_NAME" --profile="miruku_$PROJECT_NAME" --db_server='@server_localhost'

	drush @hostmaster hosting-dispatch
	echo
	
	# Install site (init DB, etc.)
	echo "drush @$PROJECT_DOMAIN provision-install -d -v"
	echo
	cd $PROJECT_PLATFORM
	drush "@$PROJECT_DOMAIN" provision-install -d -v
	drush @hostmaster hosting-dispatch
	echo
	
	
	# Verify the platform to auto-'import' the site in the frontend
	echo "drush @hostmaster hosting-task @platform_$PROJECT_NAME verify"
	drush @hostmaster hosting-task @platform_$PROJECT_NAME verify --force
	drush @hostmaster hosting-dispatch
	echo
	
	# Supply an admin reset password address
	cd $PROJECT_PLATFORM/sites/$PROJECT_DOMAIN
	echo "* One-time login url:"
	drush user-login 
	echo
}

dependencies
getoptions "$@"
setvariables
if [ "$SCRIPT_TASK" = "a" ]; then makethings ; fi
aegirthings
