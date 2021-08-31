#!/usr/local/bin/Rscript

# This Rscript will download the latest synoptic JSON file from Purple Air. 
#
# See test/Makefile for testing options
#

#  ---- . AirSensor 0.9.x . updated PAS baseUrl
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
    archiveBaseDir = file.path(getwd(), "data"),
    logDir = file.path(getwd(), "logs"),
    spatialDataDir = "~/Data/Spatial",
    version = FALSE
  )  
  
} else {
  
  # Set up OptionParser
  library(optparse)

  option_list <- list(
    make_option(
      c("-o","--archiveBaseDir"), 
      default = getwd(), 
      help = "Output base directory for generated .RData files [default = \"%default\"]"
    ),
    make_option(
      c("-l","--logDir"), 
      default = getwd(), 
      help = "Output directory for generated .log file [default = \"%default\"]"
    ),
    make_option(
      c("-s","--spatialDataDir"), 
      default = "/home/mazama/data/Spatial", 
      help = "Directory containing spatial datasets used by MazamaSpatialUtils [default = \"%default\"]"
    ),
    make_option(
      c("-V","--version"), 
      action = "store_true", 
      default = FALSE, 
      help = "Print out version number [default = \"%default\"]"
    )
  )
  
  # Parse arguments
  opt <- parse_args(OptionParser(option_list = option_list))
  
}

# Print out version and quit
if ( opt$version ) {
  cat(paste0("createPAS_exec.R ", VERSION, "\n"))
  quit()
}

# ----- Validate parameters ----------------------------------------------------

if ( !dir.exists(opt$archiveBaseDir) ) 
  stop(paste0("archiveBaseDir not found:  ", opt$archiveBaseDir))

if ( !dir.exists(opt$logDir) ) 
  stop(paste0("logDir not found:  ", opt$logDir))

if ( !dir.exists(opt$spatialDataDir) ) 
  stop(paste0("spatialDataDir not found:  ", opt$spatialDataDir))

# ----- Set up logging ---------------------------------------------------------

logger.setup(
  traceLog = file.path(opt$logDir, "createPAS_TRACE.log"),
  debugLog = file.path(opt$logDir, "createPAS_DEBUG.log"), 
  infoLog  = file.path(opt$logDir, "createPAS_INFO.log"), 
  errorLog = file.path(opt$logDir, "createPAS_ERROR.log")
)

# For use at the very end
errorLog <- file.path(opt$logDir, "createPAS_ERROR.log")

if ( interactive() ) {
  logger.setLevel(TRACE)
}
  
# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createPAS_exec.R version %s\n",VERSION)
optString <- paste(capture.output(str(opt)), collapse = "\n")
logger.debug("Script options: \n\n%s\n", optString)
sessionString <- paste(capture.output(sessionInfo()), collapse = "\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ------ Create PAS ------------------------------------------------------------

# All datestamps are UTC
timezone <- "UTC"

result <- try({
  
  # Set up MazamaSpatialUtils
  AirSensor::initializeMazamaSpatialUtils(opt$spatialDataDir)
  
  # Save it with the UTC YYYYmmdd stamp
  datestamp <- strftime(lubridate::now(tzone = timezone), "%Y%m%d", tz = timezone)
  monthstamp <- stringr::str_sub(datestamp, 1, 6)
  yearstamp <- stringr::str_sub(datestamp, 1, 4)
  
  # Create directory if it doesn't exist
  outputDir <- file.path(opt$archiveBaseDir, "pas", yearstamp)
  if ( !dir.exists(outputDir) ) {
    dir.create(outputDir, recursive = TRUE)
  }
  logger.info("Output directory: %s", outputDir)
  
  logger.info("Creating 'pas' data for %s", datestamp)
  
  # Get archival PAS data
  pas <- pas_createNew(
    countryCodes = c('US'),
    includePWFSL = TRUE,
    lookbackDays = 1e6, # ~720 BC. Rome was in its youth.
    baseUrl = 'https://www.purpleair.com/json?tempAccess5=true'
  )

  # Save the archival version
  filename <- paste0("pas_", datestamp, "_archival.rda")
  filepath <- file.path(outputDir, filename)
  logger.info("Writing PAS data to %s", filename)
  save(list = "pas", file = filepath)

  # Filter for those seen in the last week
  starttime <- lubridate::now(tzone = "UTC") - lubridate::ddays(7)
  pas <- dplyr::filter(pas, .data$lastSeenDate >= starttime)

  # Save the "latest" version
  filename <- paste0("pas_", datestamp, ".rda")
  filepath <- file.path(outputDir, filename)
  logger.info("Writing PAS data to %s", filename)
  save(list = "pas", file = filepath)

}, silent = TRUE)

# Handle errors
if ( "try-error" %in% class(result) ) {
  msg <- paste("Error creating daily PAS file: ", geterrmessage())
  logger.fatal(msg)
} else {
  # Guarantee that the errorLog exists
  if ( !file.exists(errorLog) ) dummy <- file.create(errorLog)
  logger.info("Completed successfully!")
}

