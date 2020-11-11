################################################################################
# Makefile for configuring scripts in local_executables
#

# Set variables
ARCHIVE_BASE_DIR:=/var/www/html/PurpleAir/v1

EXEC_DIR:=/root/AQ-SPEC-sensor-data-ingest-v1

DAILY_CRONTAB:=crontab_daily_DO.txt

# Targets
docker_image:
	docker pull mazamascience/airsensor:1.0.3
	docker tag mazamascience/airsensor:1.0.3 mazamascience/airsensor:latest

base_dir:
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/logs
	touch $(ARCHIVE_BASE_DIR)/logs/cron_log.txt

scripts:
	chmod +x createAirSensor_annual_exec.R
	chmod +x createAirSensor_extended_exec.R
	chmod +x createAirSensor_latest_exec.R
	chmod +x createPAS_exec.R
	chmod +x createPAT_extended_exec.R
	chmod +x createPAT_latest_exec.R
	chmod +x createPAT_monthly_exec.R
	chmod +x createVideo_exec.R

crontab:
	crontab crontab $(EXEC_DIR)/crontabs_etc/$(DAILY_CRONTAB)

configure: docker_image base_dir scripts crontab
	
