#!/usr/local/bin/Rscript

# This Rscript will process archived 'pat' data files into a single 'airsensor'
# airsensor_<collection-id>_latest7.rda file containing hourly aggregated pm25
# data for all sensors.
#
# See test/Makefile for testing options
#

#  ----- . AirSensor 0.9.x . minor refactor
VERSION = "0.2.6"

# The following packages are attached here so they show up in the sessionInfo
suppressPackageStartupMessages({
  library(MazamaCoreUtils)
  library(AirSensor)
})

# ----- Get command line arguments ---------------------------------------------

if ( interactive() ) {
  
  # RStudio session
  opt <- list(
    archiveBaseDir = file.path(getwd(), "test/output"),
    logDir = file.path(getwd(), "test/logs"),
    countryCode = "US",
    stateCode = "CA",
    pattern = "^[Ss][Cc].._..$",
    collectionName = "scaqmd",
    version = FALSE
  )  
  
} else {
  
  # Set up OptionParser
  library(optparse)
  
  option_list <- list(
    optparse::make_option(
      c("-o","--archiveBaseDir"), 
      default = getwd(), 
      help = "Output directory for generated .RData files [default = \"%default\"]"
    ),
    optparse::make_option(
      c("-l","--logDir"), 
      default = getwd(), 
      help = "Output directory for generated .log file [default = \"%default\"]"
    ),
    optparse::make_option(
      c("-c","--countryCode"), 
      default = "US", 
      help = "Two character countryCode used to subset sensors [default = \"%default\"]"
    ),
    optparse::make_option(
      c("-s","--stateCode"), 
      default = "CA", 
      help = "Two character stateCode used to subset sensors [default = \"%default\"]"
    ),
    optparse::make_option(
      c("-p","--pattern"), 
      default = "^[Ss][Cc].._..$", 
      help = "String pattern passed to stringr::str_detect [default = \"%default\"]"
    ),
    optparse::make_option(
      c("-n","--collectionName"), 
      default = "scaqmd", 
      help = "Name associated with this collection of sensors [default = \"%default\"]"
    ),
    optparse::make_option(
      c("-V","--version"), 
      action = "store_true", 
      default = FALSE, 
      help = "Print out version number [default = \"%default\"]"
    )
  )
  
  # Parse arguments
  opt <- optparse::parse_args(optparse::OptionParser(option_list = option_list))
  
}

# Print out version and quit
if ( opt$version ) {
  cat(paste0("createAirSensor_latest_exec.R ",VERSION,"\n"))
  quit()
}

# ----- Validate parameters ----------------------------------------------------

if ( dir.exists(opt$archiveBaseDir) ) {
  setArchiveBaseDir(opt$archiveBaseDir)
} else {
  stop(paste0("archiveBaseDir not found:  ",opt$archiveBaseDir))
}

if ( !dir.exists(opt$logDir) ) 
  stop(paste0("logDir not found:  ",opt$logDir))

# ----- Set up logging ---------------------------------------------------------

logger.setup(
  traceLog = file.path(opt$logDir, paste0("createAirSensor_latest_",opt$collectionName,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createAirSensor_latest_",opt$collectionName,"_DEBUG.log")), 
  infoLog  = file.path(opt$logDir, paste0("createAirSensor_latest_",opt$collectionName,"_INFO.log")),
  errorLog = file.path(opt$logDir, paste0("createAirSensor_latest_",opt$collectionName,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createAirSensor_latest_",opt$collectionName,"_ERROR.log"))

if ( interactive() ) {
  logger.setLevel(TRACE)
}

# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createAirSensor_latest_exec.R version %s",VERSION)
optString <- paste(capture.output(str(opt)), collapse = "\n")
logger.debug("Script options: \n\n%s\n", optString)
sessionString <- paste(capture.output(sessionInfo()), collapse = "\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ------ Create AirSensor objects ----------------------------------------------

# Create directory if it doesn't exist
tryCatch(
  expr = {
    outputDir <- file.path(opt$archiveBaseDir, "airsensor", "latest")
    if ( !dir.exists(outputDir) ) {
      dir.create(outputDir, recursive = TRUE)
    }
    logger.info("Output directory: %s", outputDir)
  }, 
  error = function(e) {
    msg <- paste('Error validating output directory: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# Load PAS object 
tryCatch(
  expr = {
    logger.info('Loading PAS data...')
    pas <- 
      pas_load() %>%
      pas_filter(.data$countryCode == opt$countryCode)
  }, 
  error = function(e) {
    msg <- paste('Fatal PAS Load Execution: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# Subset by state if reqeusted
if ( !is.null(opt$stateCode) )
  pas <- pas_filter(pas, .data$stateCode == opt$stateCode)
  
# Capture Unique IDs
tryCatch(
  expr = {
    # Get time series unique identifiers
    deviceDeploymentIDs <-
      pas %>%
      pas_filter(.data$DEVICE_LOCATIONTYPE == "outside") %>%
      pas_filter(is.na(.data$parentID)) %>%
      pas_filter(stringr::str_detect(.data$label, opt$pattern)) %>%
      dplyr::pull(.data$deviceDeploymentID)
  },
  error = function(e) {
    msg <- paste('deviceDeploymentID not found: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

logger.info('Creating airsensors...')

# Init counts
successCount <- 0
count <- 0

dataList <- list()

for ( deviceDeploymentID in deviceDeploymentIDs ) {
  
  count <- count + 1
  
  # Debug info
  logger.debug(
    "%4d/%d pat_createAirSensor(id = '%s')",
    count,
    length(deviceDeploymentIDs),
    deviceDeploymentID
  )
  
  # Load the pat data, convert to an airsensor and add to dataList
  dataList[[deviceDeploymentID]] <- tryCatch(
    expr = {
      pat_loadLatest(id = deviceDeploymentID) %>% 
        pat_createAirSensor(
          FUN = AirSensor::PurpleAirQC_hourly_AB_01
        )
    }, 
    error = function(e) {
      logger.warn('Unable to load PAT data for %s ', deviceDeploymentID)
      NULL
    }
  )
  
}


# Combine the airsensors to a single ws_monitor opbject and save
tryCatch(
  expr = {
    logger.info('Combining airsensors...')
    
    airsensor <- PWFSLSmoke::monitor_combine(dataList)
    class(airsensor) <- c("airsensor", "ws_monitor", "list")
    
    logger.info('Combined successfully...')
    
    filename <- paste0("airsensor_", opt$collectionName, "_latest7.rda")
    filepath <- file.path(outputDir, filename)
    
    save(list = "airsensor", file = filepath)
    logger.info("Saved: %s", filename)
  }, 
  error = function(e) {
    msg <- paste("Error creating latest AirSensor file: ", e)
    logger.fatal(msg)
  }
)

# Guarantee that the errorLog exists
if ( !file.exists(errorLog) ) dummy <- file.create(errorLog)
logger.info("Completed successfully!")

