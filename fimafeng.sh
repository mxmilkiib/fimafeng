#!/bin/bash

# Aegir FF (Fimafeng), devprovision helper script by Milk Miruku
# report bugs via https://github.com/milkmiruku/fimafeng, thank you

# /var/aegir/ff - containing this script
# ff/base - containing base make/info files
# ff/projects - contains origin git repos for config (copied from base files) and theme

# required:
# ff/shflags http://code.google.com/p/shflags/

# changelog
# 0.3 - big refactor, included base profiles, etc., added changelog

# todo;
# - fix removing platforms
# - fix logging
# - make certain it doesn't break things
# - etc.

#logfile=logs/ff_.log
#exec > $logfile 2>&1

#testing:
#set -e # Don't plow on after errors
#set -v mode # prints commands to be executed to stderr, prints everything before anything ( substitutions and expansions, ...) big is applied
#set -x mode 

### Bashtrap for cleaning up after ctrl-c

# trap bashtrap INT - neutered for testing
bashtrap() {
 	echo -e "\n\n*** Exiting script, removing files"
	if [ "$FF_STAGE" = "stage1_begin" ];then
		exit
	elif [ "$FF_STAGE" = "stage2_makeproject" ];then
		if [ "$SCRIPT_TASK" = "a" ]; then rm -rf $PROJECT_PATH ; fi
		echo
		exit
	elif [ "$FF_STAGE" = "stage3_aegirthings_platform_files" ];then
		if [ "$SCRIPT_TASK" = "a" ]; then rm -rf $PROJECT_PATH ; fi
		rm -rf $PLATFORM_PATH
		echo
		exit
	elif [ "$FF_STAGE" = "stage4_aegirthings_platform_filesdrush" ];then
		# Removes Drush platform alias
		drush provision-save "@platform_"$PLATFORM_NAME"" --root="$PLATFORM_PATH" --delete
		drush @hostmaster hosting-dispatch
		
		if [ "$SCRIPT_TASK" = "a" ]; then rm -rf $PROJECT_PATH ; fi
		rm -rf $PLATFORM_PATH
		echo
		exit
	elif [ "$FF_STAGE" = "stage5_aegirthings_platform_filesdrushsite" ];then
		# Removes site files, db and vhost
		drush "@$SITE_DOMAIN" provision-delete 
		# Removes Drush site alias
		drush provision-save --root="$PLATFORM_PATH" "@$SITE_DOMAIN" --delete
		
		# Removes Drush platform alias
		drush provision-save "@platform_"$PLATFORM_NAME"" --root="$PLATFORM_PATH" --delete
		drush @hostmaster hosting-dispatch

		rm -rf $PROJECT_PATH
		rm -rf $PLATFORM_PATH
		echo
		exit
	fi
}


# Call script functions
scriptprocess() {
  dependencies
  getoptions "$@"
  variablechecks "$@"

  if [ "$SCRIPT_TASK" = "a" ]; then makeproject ; fi
  if [ "$SCRIPT_TASK" = "a" ] || [ "$SCRIPT_TASK" = "b" ]; then aegirplatform ; fi
  if [ "$SCRIPT_TASK" = "a" ] || [ "$SCRIPT_TASK" = "b" ] || [ "$SCRIPT_TASK" = "c" ]; then aegirsite ; fi

  if [ "$SCRIPT_TASK" = "rc" ]; then removesite ; fi
  if [ "$SCRIPT_TASK" = "rb" ]; then removeplatform ; fi
  if [ "$SCRIPT_TASK" = "ra" ]; then removeproject ; fi
  if [ "$SCRIPT_TASK" = "rcb" ]; then removesite ; removeplatform ; fi
  if [ "$SCRIPT_TASK" = "rcba" ]; then removesite ; removeplatform ; removeproject ; fi 
}


# Check user is aegir
dependencies() {
	if [ `whoami` != "aegir" ]; then
		echo "This script should be ran as the aegir user."
		exit 1
	fi

# projects folder exist?
  if [ ! -d ./projects ]; then echo "no projects folder!"; fi

}


# Set options from command line input

getoptions() {
  # source shflags -  http://code.google.com/p/shflags/wiki/Documentation10x
  . shflags-1.0.3/src/shflags

  # define command-line string flags
  DEFINE_string 'project' '' 'Project name (no spaces, hyphens)' 'p'
  DEFINE_string 'platform' '' 'Platform name (default is project name)' 'l'
  DEFINE_string 'domain' '' 'Site domain name' 'a'
  DEFINE_string 'task' '' 'Task to perform.
            a - Create project, build platform and provision site
            b - Use existing project, build platform and provision site
            c - Use existing project and platform, provision site
            rc - Removing site
            rb - Removing platform
            ra - Removing project' 'o'
  DEFINE_string 'drupal' '7' 'Drupal version (default is D7)' 'd'
  DEFINE_boolean 'verbose' 'false' 'Verbose mode for Git and Drush' 'v'
  DEFINE_boolean 'usage' 'false' 'Usage string examples' 'u'
  DEFINE_boolean 'interactive' 'true' 'Set this for autopilot' 'i'
  DEFINE_string 'theme' 'DEFAULT' 'Base theme to use' 't'
  DEFINE_string 'themebranch' '' 'Branch of theme to use' 'b'

  # parse the command-line
  FLAGS "$@" || exit 1
  # things that could not be parsed
  eval set -- "${FLAGS_ARGV}"

  # set variables
  PROJECT_NAME="${FLAGS_project}"                                             # Required
  PLATFORM_NAME="${FLAGS_platform}"                                           # Required
  SITE_DOMAIN="${FLAGS_domain}"                                               # Required
  SCRIPT_TASK="${FLAGS_task}"                                                 # Required
  DRUPAL_VERSION="${FLAGS_drupal}"
  BASE_THEME="${FLAGS_theme}"
  BASE_THEME_BRANCH="${FLAGS_themebranch}"
  VERBOSE_MODE="${FLAGS_verbose}"
  USAGE_MODE="${FLAGS_usage}"
  INTERACTIVE_MODE="${FLAGS_interactive}"

	# Date string; year, month, day, hours, seconds
	DATE="date +%Y%m%d%H%M%S"
  # Not used yet
  
  if [ "$USAGE_MODE" == "0" ]; then
    echo "Fimafeng usage examples:" 
    echo " ./fimafeng.sh -p test -l test -a test.example.org -o a"
    exit
  fi

}


# check everything is ok
variablechecks() {
	FF_STAGE=stage1_begin                              	                      # Script stage counter

	if [ -z "$PROJECT_NAME" ] || [ -z "$PLATFORM_NAME" ]  || [ -z "$SITE_DOMAIN" ] || [ -z "$SCRIPT_TASK" ] ; then
		echo " Task fail: missing some argument"
    echo ""
    flags_help
    echo ""
		echo "Arguments: $@"
	  exit 1
	fi

  #if [ -n  "$PLATFORM_NAME" ] ; then PLATFORM_NAME=$PROJECT_NAME ; fi       # If platform is not used, project name becomes platform name

	if [ "$BASE_THEME" = "DEFAULT" ] ; then                                   # If no theme is set, use garland for D6, squaregrid for D7
  	if [ "$DRUPAL_VERSION" = "6" ]; then BASE_THEME="om" ; BASE_THEME_BRANCH="6.x-2.x"  ; fi
	  if [ "$DRUPAL_VERSION" = "7" ]; then BASE_THEME="sasson" ; BASE_THEME_BRANCH="7.x-2.x" ; fi
  fi

	AEGIR_PATH=$HOME                                       	                  # The Aegir dir, typically /var/aegir
  FF_PATH="$AEGIR_PATH/ff"                                                  # Path of this script

  if [ "$DRUPAL_VERSION" = "6" ]; then BASE_PROJECT=$FF_PATH/base/d6core.git/ ; fi
  if [ "$DRUPAL_VERSION" = "7" ]; then BASE_PROJECT=$FF_PATH/base/d7core.git/ ; fi

  if [ ! -d "$BASE_PROJECT" ]; then echo "$BASE_PROJECT doesn't exist, exiting" ; fi

	# Project profile Git folder for .make, .info, .profile and theme folders
 	PROJECT_PATH=$FF_PATH/projects/$PROJECT_NAME.git                          # /var/aegir/ff/projects/projectname.git

	THEMES_PATH=$PROJECT_PATH/themes
	SUB_THEME=$THEMES_PATH/$PROJECT_NAME                                      # Project subtheme folder

	PROJECT_MAKE=$PROJECT_PATH/$PROJECT_NAME.make                             # Distro .make
	PROJECT_INFO=$PROJECT_PATH/$PROJECT_NAME.info                             # Distro .info
	PROJECT_PROFILE=$PROJECT_PATH/$PROJECT_NAME.profile                       # Distro .profile, used by profiler library

	PLATFORM_PATH=$AEGIR_PATH/platforms/$PLATFORM_NAME                        # Project platform folder

  SITE_PATH=$PLATFORM_PATH/sites/$SITE_DOMAIN

  echo "Fimafeng provision script for Aegir"
  echo ""
	echo " Project: $PROJECT_NAME"
  echo " Platform: $PLATFORM_NAME"
	echo " Domain: $SITE_DOMAIN"
	echo " Drupal: $DRUPAL_VERSION"
  echo "" 
	echo -n " Task"
  if [ "$SCRIPT_TASK" == "a" ]; then
    echo ": a - Create project, build platform and provision site"
    if [ -d "$PROJECT_PATH" ] ; then echo " Build fail: project already exists" ; exit 1 ; fi
  elif [ "$SCRIPT_TASK" == "b" ]; then 
    echo ": b - Use existing project, build platform and provision site"
    if [ -d "$PLATFORM__PATH" ]; then echo " Build fail: platform already exists" ; exit 1 ; fi
  elif [ "$SCRIPT_TASK" == "c" ]; then 
    echo ": c - Use existing project and platform, provision site"
    if  [ -d "$SITE_PATH" ]; then echo " Build fail: site aready exists" ; exit 1 ; fi
  elif [ "$SCRIPT_TASK" == "rc" ] ; then echo ": rc - Removing site"
  elif [ "$SCRIPT_TASK" == "rb" ] ; then echo ": rb - Removing platform"
  elif [ "$SCRIPT_TASK" == "ra" ] ; then echo ": ra - Removing project"
  elif [ "$SCRIPT_TASK" == "rcb" ] ; then echo ": rcd - Removing site and platform"
  elif [ "$SCRIPT_TASK" == "rcba" ] ; then echo ": rcba - Removing site, platform and project"
  else echo " fail: $SCRIPT_TASK" ; exit 1 ; fi
	if [ "$VERBOSE_MODE" == "0" ]; then
    echo ""
    echo " Verbose mode: on"
    echo " Aegir: $AEGIR_PATH"
    echo " FF: $FF_PATH"
    echo ""
    echo " Project path: $PROJECT_PATH"
    echo " Project make: $PROJECT_MAKE"
    echo " Project info: $PROJECT_INFO"
    echo " Project profile: $PROJECT_PROFILE"
    echo " Subtheme: $SUB_THEME"
    echo ""
    echo " Platform path: $PLATFORM_PATH"
    echo " Site path: $SITE_PATH"
    VERBOSE_MODE="-v"
  else VERBOSE_MODE="" ; fi
  ifinteractive
}

makeproject() {
	# Script stage counter
	FF_STAGE=stage2_makeproject
	
	# Git clone project theme from FF base
	git clone -l --no-hardlinks $BASE_PROJECT $PROJECT_PATH

	# Move files for new project 
	mv $PROJECT_PATH/base.make $PROJECT_MAKE
	mv $PROJECT_PATH/base.profile $PROJECT_PROFILE
	mv $PROJECT_PATH/base.info $PROJECT_INFO
	
	# Edit .make title
	eval "sed -i s#base.make#$PROJECT_NAME.make# $PROJECT_MAKE"
	
  # Edit .make profile title, download url
  eval "sed -i s#profile_base#$PROJECT_NAME#g $PROJECT_MAKE"
	eval "sed -i s#profile_git_location#$PROJECT_PATH# $PROJECT_MAKE"

	# Edit .info for Profile settings
	eval "sed -i s#Base#$PROJECT_NAME#g $PROJECT_INFO"
	eval "sed -i s#base_theme#$PROJECT_NAME#g $PROJECT_INFO"
	
	# Edit .profile name argument
	eval "sed -i s#yourprofile#$PROJECT_NAME# $PROJECT_PROFILE"
	
	# Ask if any changes need to be made to the .make
	echo
	echo "* Edit project .make and .info if required"
  ifinteractive

	# Setup theme submodule
	cd $PROJECT_PATH
  git submodule add http://git.drupal.org/project/$BASE_THEME.git themes/$BASE_THEME
  cd themes/$BASE_THEME ; git checkout $BASE_THEME_BRANCH
  
#	echo "; $BASE_THEME subtheme" > $PROJECT_NAME.info
#	echo "" >> $PROJECT_NAME.info
#	echo "name = $PROJECT_NAME" >> $PROJECT_NAME.info
#	echo "description = $BASE_THEME subtheme for $PROJECT_NAME" >> $PROJECT_NAME.info
# echo "core = $DRUPAL_VERSION.x" >> $PROJECT_NAME.info
#	echo "engine = phptemplate" >> $PROJECT_NAME.info
#	echo "base theme = $BASE_THEME" >> $PROJECT_NAME.info
#	echo "" >> $PROJECT_NAME.info
#	echo "stylesheets[all][] = css/$PROJECT_NAME.css" >> $PROJECT_NAME.info
#	mkdir css
#	touch css/$PROJECT_NAME.css

	# cp ../$BASE_THEME/template.php template.php
	#	eval "sed -i s#YOURTHEMENAME#$PROJECT_NAME#g template.php"

	# Ask to manually edit the theme before comitting
  echo
	echo "* Edit theme if so required"
  ifinteractive

  cd $PROJECT_PATH
  # Remove files deleted from staging from repo	
	git ls-files --deleted | xargs git rm
	# Add all files in folder respecting .gitignore, so not using --all
	git add .
	# Make the commit
	git commit -m "First commit; project $PROJECT_NAME"
	echo
}


### Create and Aegerise site

aegirplatform() {
	echo "* Provisioning platform and site now"
	echo
	
	# Set the queue to run every 1 second, so we can force the dispatch command
	drush -y @hostmaster vset hosting_queue_tasks_frequency 1
	echo
	
	# Build platform with Drush Make
	FF_STAGE=stage3_aegirthings_platform_files
	echo "drush make --working-copy $PROJECT_MAKE $PLATFORM_PATH"
  ifinteractive
	drush make --working-copy "$PROJECT_MAKE" "$PLATFORM_PATH" "$VERBOSE_MODE" --debug

  if [ ! -d "$PLATFORM_PATH" ] then echo "Build fail; no platform path"; exit ; fi

  ifinteractive
	# Set an Aegir context for that platform
	FF_STAGE=stage4_aegirthings_platform_filesdrush
	echo "drush provision-save "@platform_"$PLATFORM_NAME"" --root=""$PLATFORM_PATH"" --context_type=platform'"
  ifinteractive
	drush provision-save "@platform_"$PLATFORM_NAME"" --root="$PLATFORM_PATH" --context_type=platform "$VERBOSE_MODE"
	drush @hostmaster hosting-dispatch
	
	# Import that platform into hostmaster, the Aegir frontend
	echo "drush @hostmaster hosting-import '@platform_"$PLATFORM_NAME"'"
  ifinteractive
	drush @hostmaster hosting-import "@platform_"$PLATFORM_NAME"" "$VERBOSE_MODE"
	drush @hostmaster hosting-dispatch
	echo
}

aegirsite() {
	# Set a site context in Aegir using the new platform and profile
	FF_STAGE=stage5_aegirthings_platform_filesdrushsite
	echo "drush provision-save @$SITE_DOMAIN --uri='$SITE_DOMAIN' --context_type='site' --platform='@platform_"$PLATFORM_NAME"' --profile='$PROJECT_NAME' --db_server=@server_master" "$VERBOSE_MODE"
  ifinteractive
	drush provision-save "@$SITE_DOMAIN" --uri="$SITE_DOMAIN" --context_type='site' --platform="@platform_"$PLATFORM_NAME"" --profile="$PROJECT_NAME" "$VERBOSE_MODE" --debug

	drush @hostmaster hosting-dispatch
  ifinteractive
	# Install site (init DB, etc.)
  # context then command
	cd $PLATFORM_PATH
	echo "drush @$SITE_DOMAIN provision-install"
  drush "@$SITE_DOMAIN" provision-install "$VERBOSE_MODE"
	drush @hostmaster hosting-dispatch
	echo
	
	cp $FF_PATH/base/local.settings.php $PLATFORM_PATH/sites/$SITE_DOMAIN/
	
	# Verify the platform to auto-'import' the site in the frontend test.
	echo "drush @hostmaster hosting-task @platform_"$PLATFORM_NAME" verify"
	drush @hostmaster hosting-task @platform_"$PLATFORM_NAME" verify --force "$VERBOSE_MODE"
	echo
	
	# Supply an admin reset password address
	cd $PLATFORM_PATH/sites/$SITE_DOMAIN
	echo "* One-time login url:"
	drush user-login 
	echo
}


# Removing things

removesite() {
	echo "* Removing site: drush @hostmaster hosting-task @"$SITE_DOMAIN" delete --force"
  ifinteractive
	# Create delete site task in hostmaster
	drush @hostmaster hosting-task @"$SITE_DOMAIN" delete --force
	drush @hostmaster hosting-dispatch
}


removeplatform() {
	echo "* Removing platform: drush @hostmaster hosting-task @platform_"$PLATFORM_NAME" delete --force"
  ifinteractive
	# Create delete platform task in hostmaster
	drush @hostmaster hosting-task @platform_"$PLATFORM_NAME" delete --force 
	drush @hostmaster hosting-dispatch --debug
}


removeproject() {
	echo "* Removing project folder"
 	if [ -d $PROJECT_PATH ]; then rm -rf $PROJECT_PATH ;
  else echo "No project to remove"
  fi
  echo
  exit
}

ifinteractive() {
  if [ "$INTERACTIVE_MODE" = "0" ]; then 
    echo ""
    read -p "*** Press return to continue";
    echo ""
  fi
}

# Run the script
scriptprocess "$@"
