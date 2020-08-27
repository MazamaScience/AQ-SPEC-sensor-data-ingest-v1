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
	-rm -rf output
	-rm -rf logs

setup:
	-mkdir -p output
	-mkdir -p logs

################################################################################
# PAS objects

createPAS: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createPAS_exec.R --archiveBaseDir=/app/output --logDir=/app/logs

################################################################################
# PAT objects

createPAT_latest: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createPAT_latest_exec.R --archiveBaseDir=/app/output --logDir=/app/logs --stateCode=CA --pattern=^SC.._..

createPAT_extended: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createPAT_extended_exec.R --archiveBaseDir=/app/output --logDir=/app/logs --stateCode=CA --pattern=^SC.._..

createPAT_201904: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createPAT_monthly_exec.R --archiveBaseDir=/app/output --logDir=/app/logs --datestamp=201904 --stateCode=CA --pattern=^SCNP_..

createPAT_201710: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createPAT_monthly_exec.R --archiveBaseDir=/app/output --logDir=/app/logs --datestamp=201710 --stateCode=CA --pattern=^SCSB_..

################################################################################
# AirSensor objects

createAirSensor_latest: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createAirSensor_latest_exec.R --archiveBaseDir=/app/output --logDir=/app/logs --collectionName=scaqmd --stateCode=CA --pattern=^SC.._..

createAirSensor_extended: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createAirSensor_extended_exec.R --archiveBaseDir=/app/output --logDir=/app/logs --collectionName=scaqmd

createAirSensor_201904: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createAirSensor_monthly_exec.R --archiveBaseDir=/app/output --logDir=/app/logs --datestamp=201904 --stateCode=CA --pattern=^SCNP_..

createAirSensor_annual: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createAirSensor_annual_exec.R --archiveBaseDir=/app/output --logDir=/app/logs --collectionName=scaqmd

################################################################################
# Videos

createVideo: setup
	docker run --rm -v $(BASE_PATH):/app -v $(BASE_PATH)/test/output:/app/output -v $(BASE_PATH)/test/logs:/app/logs -w /app mazamascience/airsensor:latest /app/createVideo_exec.R --archiveBaseDir=/app/output --logDir=/app/logs --communityID=SCNP

################################################################################
# main targets

show_output:
	echo ""
	cd $(BASE_PATH)/output; find `pwd`

latest_test_suite: clean setup createPAS createPAT_latest createPAT_extended createAirSensor_latest createAirSensor_extended
	echo ""
	cd $(BASE_PATH)/output; find `pwd`

full_test_suite: clean setup createPAS createPAT_latest createPAT_extended createPAT_201904 createPAT_201710 createAirSensor_latest createAirSensor_extended
	echo ""
	cd $(BASE_PATH)/output; find `pwd`

