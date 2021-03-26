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
	

################################################################################
# Targets for the data archive under ARCHIVE_BASE_DIR

create_archive_dirs:
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/airsensor/2017
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/airsensor/2018
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/airsensor/2019
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/airsensor/2020
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/airsensor/latest
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/logs
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/pas/2019
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/pas/2020
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/pat/2017
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/pat/2018
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/pat/2019
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/pat/2020
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/pat/latest
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/videos/2017
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/videos/2018
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/videos/2019
	sudo mkdir -p $(ARCHIVE_BASE_DIR)/videos/2020

install_airsensor_archive:
	sudo wget --directory-prefix $(ARCHIVE_BASE_DIR)/airsensor --no-clobber --no-parent --no-host-directories --recursive --level=2 --cut-dirs=3 --reject "index.html*" --accept "*.rda" http://data.mazamascience.com/PurpleAir/v1/airsensor

install_pas_archive:
	sudo wget --directory-prefix $(ARCHIVE_BASE_DIR)/pas --no-clobber --no-parent --no-host-directories --recursive --level=2 --cut-dirs=3 --reject "index.html*" --accept "*.rda" http://data.mazamascience.com/PurpleAir/v1/pas

install_pat_archive:
	sudo wget --directory-prefix $(ARCHIVE_BASE_DIR)/pat --no-clobber --no-parent --no-host-directories --recursive --level=3 --cut-dirs=3 --reject "index.html*" --accept "*.rda" http://data.mazamascience.com/PurpleAir/v1/pat

install_video_archive:
	sudo wget --directory-prefix $(ARCHIVE_BASE_DIR)/videos --no-clobber --no-parent --no-host-directories --recursive --level=3 --cut-dirs=3 --reject "index.html*" --accept "*.mp4" http://data.mazamascience.com/PurpleAir/v1/videos

# NOTE:  The old archive doesn't have month-level directories
#install_old_video_archive:
#	sudo wget --directory-prefix $(ARCHIVE_BASE_DIR)/videos --no-clobber --no-parent --no-host-directories --recursive --level=3 --cut-dirs=3 --reject "index.html*" --accept "*.mp4" http://smoke.mazamascience.com/data/PurpleAir/videos
