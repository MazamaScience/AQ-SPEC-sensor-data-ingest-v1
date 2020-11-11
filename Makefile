################################################################################
# Makefile for configuring scripts in local_executables
#

# Set variables
ARCHIVE_BASE_DIR:=/var/www/html/data/PurpleAir

EXEC_DIR:=/root/AQ-SPEC-sensor-data-ingest-v1

# Targets
docker_image:
	docker pull mazamascience/airsensor:1.0.3
	docker tag mazamascience/airsensor:1.0.3 mazamascience/airsensor:latest

base_dir:
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/logs

scripts:
	chmod +x createAirSensor_annual_exec.R
	chmod +x createAirSensor_extended_exec.R
	chmod +x createAirSensor_latest_exec.R
	chmod +x createPAS_exec.R
	chmod +x createPAT_extended_exec.R
	chmod +x createPAT_latest_exec.R
	chmod +x createPAT_monthly_exec.R
	chmod +x createVideo_exec.R

configure: docker_image base_dir scripts
	
