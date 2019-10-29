#!/usr/local/bin/Rscript

# This Rscript will process archived 'pat' data files into a single 'airsensor'
# file containing hourly data for all sensors.
#
# See test/Makefile for testing options
#

#  ----- . ----- . scaqmd version
VERSION = "0.1.3"

library(optparse)      # to parse command line flags

# The following packages are attached here so they show up in the sessionInfo
suppressPackageStartupMessages({
  library(futile.logger)
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
    make_option(
      c("-o","--archiveBaseDir"), 
      default = getwd(), 
      help = "Output directory for generated .RData files [default = \"%default\"]"
    ),
    make_option(
      c("-l","--logDir"), 
      default = getwd(), 
      help = "Output directory for generated .log file [default = \"%default\"]"
    ),
    make_option(
      c("-s","--stateCode"), 
      default = "CA", 
      help = "Two character stateCode used to subset sensors [default = \"%default\"]"
    ),
    make_option(
      c("-p","--pattern"), 
      default = "^[Ss][Cc].._..$", 
      help = "String pattern passed to stringr::str_detect [default = \"%default\"]"
    ),
    make_option(
      c("-n","--collectionName"), 
      default = "scaqmd", 
      help = "Name associated with this collection of sensors [default = \"%default\"]"
    ),
    make_option(
      c("-V","--version"), 
      action="store_true", 
      default = FALSE, 
      help = "Print out version number [default = \"%default\"]"
    )
  )
  
  # Parse arguments
  opt <- parse_args(OptionParser(option_list=option_list))
  
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

# ------ Create AirSensor objects ----------------------------------------------

result <- try({
  
  # Create directory if it doesn't exist
  outputDir <- file.path(opt$archiveBaseDir, "airsensor", "latest")
  if ( !dir.exists(outputDir) ) {
    dir.create(outputDir, recursive = TRUE)
  }
  logger.info("Output directory: %s", outputDir)
  
  logger.info("Loading PAS data")
  pas <- pas_load()
  
  # Find the labels of interest, only one per sensor
  labels <-
    pas %>%
    pas_filter(is.na(parentID)) %>%
    pas_filter(DEVICE_LOCATIONTYPE == "outside") %>%
    pas_filter(stateCode == opt$stateCode) %>%
    pas_filter(stringr::str_detect(label, opt$pattern)) %>%
    dplyr::pull(label)
  
  R_labels <- make.names(labels, unique = TRUE)
  
  logger.info("Loading PAT data for %d sensors", length(labels))
  
  airSensorList <- list()
  
  for ( i in seq_along(labels) ) {
    
    label <- labels[i]
    R_label <- R_labels[i]
    
    logger.trace("Working on %s", label)
    
    # Keep going even if one sensor fails to load
    result <- try({
      
      airSensorList[[R_label]] <- 
        pat_loadLatest(label, make.names = TRUE) %>%
        pat_createAirSensor(
          period = "1 hour",
          parameter = "pm25",
          channel = "ab",
          qc_algorithm = "hourly_AB_01",
          min_count = 20
        )
      
    }, silent = TRUE)
    if ( "try-error" %in% class(result) ) {
      logger.warn(geterrmessage())
    }
    
  }
  
  logger.trace("Finished creating individual sensors.")
  
  airsensor <- PWFSLSmoke::monitor_combine(airSensorList)
  class(airsensor) <- c("airsensor", "ws_monitor", "list")
  
  logger.trace("Finished combining sensors.")
  
  filename <- paste0("airsensor_", opt$collectionName, "_latest7.rda")
  filepath <- file.path(outputDir, filename)
  
  logger.info("Writing 'airsensor' data to %s", filename)
  save(list="airsensor", file = filepath)
  
}, silent=TRUE)

# Handle errors
if ( "try-error" %in% class(result) ) {
  msg <- paste("Error creating latest AirSensor file: ", geterrmessage())
  logger.fatal(msg)
} else {
  # Guarantee that the errorLog exists
  if ( !file.exists(errorLog) ) dummy <- file.create(errorLog)
  logger.info("Completed successfully!")
}

