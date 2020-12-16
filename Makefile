################################################################################
# Makefile for setting up PurpleAir data processing


# ----- Set per-server configurable variables ---------------------------------

ARCHIVE_BASE_DIR:=/var/www/html/PurpleAir/v1

EXEC_DIR:=/root/AQ-SPEC-sensor-data-ingest-v1

DAILY_CRONTAB:=crontab_daily_DO.txt


# ----- Target tasks ----------------------------------------------------------

# Install the docker image in which scripts will run
docker_image:
	docker pull mazamascience/airsensor:1.0.3
	docker tag mazamascience/airsensor:1.0.3 mazamascience/airsensor:latest

# Set up the archive base directory for data and logs
base_dir:
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/logs
	touch $(ARCHIVE_BASE_DIR)/logs/cron_log.txt

# Make sure scripts are executable
scripts:
	chmod +x $(EXEC_DIR)/createAirSensor_annual_exec.R
	chmod +x $(EXEC_DIR)/createAirSensor_extended_exec.R
	chmod +x $(EXEC_DIR)/createAirSensor_latest_exec.R
	chmod +x $(EXEC_DIR)/createPAS_exec.R
	chmod +x $(EXEC_DIR)/createPAT_extended_exec.R
	chmod +x $(EXEC_DIR)/createPAT_latest_exec.R
	chmod +x $(EXEC_DIR)/createPAT_monthly_exec.R
	chmod +x $(EXEC_DIR)/createVideo_exec.R

# Create an initial PAS object (required for PAT and AirSensor scripts)
create_pas:
	docker run --rm -v $(EXEC_DIR):/app -v $(ARCHIVE_BASE_DIR):/data -v $(ARCHIVE_BASE_DIR)/logs:/logs -w /app mazamascience/airsensor /app/createPAS_exec.R --archiveBaseDir=/data --logDir=/logs >> $(ARCHIVE_BASE_DIR)/logs/cron_log.txt 2>&1

# Load the "daily" crontab which should always be running
crontab:
	crontab $(EXEC_DIR)/crontabs_etc/$(DAILY_CRONTAB)

# Perform all tasks
install: docker_image base_dir scripts create_pas crontab
	
