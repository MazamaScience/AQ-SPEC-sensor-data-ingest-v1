#!/usr/local/bin/Rscript

# This Rscript will process archived 'pat' data files into a single 'airsensor'
# file containing hourly data for all sensors.
#
# See test/Makefile for testing options
#

#  ----- . ----- . AirSensor 0.5.16
VERSION = "0.1.4"

# The following packages are attached here so they show up in the sessionInfo
suppressPackageStartupMessages({
  library(MazamaCoreUtils)
  library(AirSensor)
})

# ----- Get command line arguments ---------------------------------------------

if ( interactive() ) {
  
  # RStudio session
  opt <- list(
    archiveBaseDir = file.path(getwd(), "output"),
    logDir = file.path(getwd(), "logs"),
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
      action="store_true", 
      default = FALSE, 
      help = "Print out version number [default = \"%default\"]"
    )
  )
  
  # Parse arguments
  opt <- optparse::parse_args(optparse::OptionParser(option_list=option_list))
  
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
  traceLog = file.path(opt$logDir, paste0("createAirSensor_",opt$collectionName,"_latest_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createAirSensor_",opt$collectionName,"_latest_DEBUG.log")), 
  infoLog  = file.path(opt$logDir, paste0("createAirSensor_",opt$collectionName,"_latest_INFO.log")),
  errorLog = file.path(opt$logDir, paste0("createAirSensor_",opt$collectionName,"_latest_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createAirSensor_",opt$collectionName,"_latest_ERROR.log"))

if ( interactive() ) {
  logger.setLevel(TRACE)
}

# Silence other warning messages
options(warn=-1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createAirSensor_latest_exec.R version %s",VERSION)
sessionString <- paste(capture.output(sessionInfo()), collapse="\n")
logger.debug("R session:\n\n%s\n", sessionString)

# Command line options
optionsString <- paste(capture.output(str(opt)), collapse='\n')
logger.debug('Command line options:\n\n%s\n', optionsString)

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
    msg <- paste('Error creating datetimes ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# Load PAS object 
tryCatch(
  expr = {
    logger.info('Loading PAS data...')
    pas <- 
      pas_load() 
  }, 
  error = function(e) {
    msg <- paste('Fatal PAS Load Execution: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

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

for ( ddID in deviceDeploymentIDs ) {
  count <- count + 1
  # Debug info
  logger.debug(
    "%4d/%d pat_createAirSensor(id = '%s')",
    count,
    length(deviceDeploymentIDs),
    ddID
  )
  
  # Load the pat data, convert to an airsensor and add to dataList
  dataList[[ddID]] <- tryCatch(
    expr = {
      pat_loadLatest(id = ddID) %>% 
        pat_createAirSensor(
          FUN = AirSensor::PurpleAirQC_hourly_AB_02
        )
    }, 
    error = function(e) {
      logger.warn('Failed: Loading PAT data for %s ', ddID)
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
    
    save(list="airsensor", file = filepath)
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
