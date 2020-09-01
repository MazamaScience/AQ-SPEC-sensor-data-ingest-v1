################################################################################
# Makefile for configuring scripts in local_executables
#

# Set variables
ARCHIVE_BASE_DIR:=/var/www/html/data/PurpleAir

EXEC_DIR:=/home/jonathan/AQ-SPEC-sensor-data-ingest-v1


################################################################################
# Create new executable scripts

configure_scripts:
	chmod +x createAirSensor_annual_exec.R
	chmod +x createAirSensor_extended_exec.R
	chmod +x createAirSensor_latest_exec.R
	chmod +x createPAS_exec.R
	chmod +x createPAT_extended_exec.R
	chmod +x createPAT_latest_exec.R
	chmod +x createPAT_monthly_exec.R
	chmod +x createVideo_exec.R

configure: configure_scripts
	
