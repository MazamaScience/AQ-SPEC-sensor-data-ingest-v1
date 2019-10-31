################################################################################
# Makefile for configuring scripts in local_executables
#

# Set variables
ARCHIVE_BASE_DIR:=/var/www/html/data/PurpleAir/v1

EXEC_DIR:=/home/jonathan/AirSensor/local_executables


################################################################################
# Create new crontab files and executable scripts
#
# NOTE:  Use "%" as the sed delimiter to avoid conflict with "/"

configure_crontabs:
	sed 's%__EXEC_DIR__%${EXEC_DIR}%g' __crontab_daily.txt | \
	    sed 's%_ARCHIVE_BASE_DI%${ARCHIVE_BASE_DIR}W%g > crontab_daily.txt

configure_scripts:
	chmod +x createAirSensor_annual_exec.R
	chmod +x createAirSensor_extended_exec.R
	chmod +x createAirSensor_latest_exec.R
	chmod +x createPAS_exec.R
	chmod +x createPAT_extended_exec.R
	chmod +x createPAT_latest_exec.R
	chmod +x createPAT_monthly_exec.R
	chmod +x createVideo_exec.R

configure: configure_crontabs configure_scripts
	
