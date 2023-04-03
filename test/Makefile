################################################################################
# Makefile for testing scripts against mazamascience/airsensor:latest
#

# A little Makefile magic from:  https://www.gnu.org/software/make/manual/html_node/File-Name-Functions.html#File-Name-Functions
BASE_PATH:=$(realpath ..)

# And a target to test it
show_base_path:
	@echo $(BASE_PATH)

# Clean up generated files
clean:
	-rm -rf data
	-rm -rf logs

setup:
	-mkdir -p data
	-mkdir -p logs

desktop_download_data: setup
	curl http://data.mazamascience.com/PurpleAir/v1/pas/2019/pas_20191001_archival.rda -o data/pas/2019/pas_20191001_archival.rda --create-dirs

################################################################################
# PAS objects

createPAS: desktop_download_data
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/data:/app/data -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createPAS_exec.R --archiveBaseDir=/app/data --logDir=/app/logs

################################################################################
# PAT objects

createPAT_latest: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/data:/app/data -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createPAT_latest_exec.R --archiveBaseDir=/app/data --logDir=/app/logs 

createPAT_extended: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/data:/app/data -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createPAT_extended_exec.R --archiveBaseDir=/app/data --logDir=/app/logs

createPAT_202212: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/data:/app/data -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createPAT_monthly_exec.R --archiveBaseDir=/app/data --logDir=/app/logs --datestamp=202212

################################################################################
# AirSensor objects

createAirSensor_latest: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/data:/app/data -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createAirSensor_latest_exec.R --archiveBaseDir=/app/data --logDir=/app/logs --collectionName=scaqmd

createAirSensor_extended: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/data:/app/data -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createAirSensor_extended_exec.R --archiveBaseDir=/app/data --logDir=/app/logs --collectionName=scaqmd

createAirSensor_202212: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/data:/app/data -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createAirSensor_monthly_exec.R --archiveBaseDir=/app/data --logDir=/app/logs --datestamp=202212

createAirSensor_annual: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/data:/app/data -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createAirSensor_annual_exec.R --archiveBaseDir=/app/data --logDir=/app/logs --collectionName=scaqmd

################################################################################
# Videos

createVideo: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/data:/app/data -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createVideo_exec.R --archiveBaseDir=/app/data --logDir=/app/logs --communityID=SCSB

################################################################################
# main targets

show_data:
	@echo ""
	@cd $(BASE_PATH)/data; find `pwd`

#latest_test_suite: clean setup createPAS createPAT_latest createPAT_extended createAirSensor_latest createAirSensor_extended
#	@echo ""
#	@cd $(BASE_PATH)/data; find `pwd`

#full_test_suite: clean setup createPAS createPAT_latest createPAT_extended createPAT_201904 createPAT_201710 createAirSensor_latest createAirSensor_extended
#	@echo ""
#	@cd $(BASE_PATH)/data; find `pwd`

