#!/usr/local/bin/Rscript

# This Rscript will ingest airsensor_~_latest7.rda files and use them to create
# airsensor files for an entire year.
#
# See test/Makefile for testing options
#

#  ----- . ----- . sensor-data-ingest
VERSION = "0.1.3"

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
    archiveBaseDir = file.path(getwd()),
    logDir = file.path(getwd()),
    datestamp = "2019",
    collectionName = "scaqmd",
    version = FALSE
  )  
  
} else {
  
  # Set up OptionParser
  library(optparse)
  
  option_list <- list(
    make_option(
      c("-o","--archiveBaseDir"), 
      default=getwd(), 
      help = "Output base directory for generated .RData files [default = \"%default\"]"
    ),
    make_option(
      c("-l","--logDir"), 
      default=getwd(), 
      help="Output directory for generated .log file [default=\"%default\"]"
    ),
    make_option(
      c("-d","--datestamp"), 
      default="", 
      help="Datestamp specifying the year as YYYY [default=current year]"
    ),
    make_option(
      c("-n","--collectionName"), 
      default="scaqmd", 
      help="Name associated with this collection of sensors [default=\"%default\"]"
    ),
    make_option(
      c("-V","--version"), 
      action="store_true", 
      default=FALSE, 
      help="Print out version number [default=\"%default\"]"
    )
  )
  
  # Parse arguments
  opt <- parse_args(OptionParser(option_list=option_list))
  
}

# Print out version and quit
if ( opt$version ) {
  cat(paste0("createAirSensor_annual_exec.R ",VERSION,"\n"))
  quit()
}

# ----- Validate parameters ----------------------------------------------------

if ( dir.exists(opt$archiveBaseDir) ) {
  setArchiveBaseDir(opt$archiveBaseDir)
} else {
  stop(paste0("archiveBaseDir not found:  ", opt$archiveBaseDir))
}

if ( !dir.exists(opt$logDir) ) 
  stop(paste0("logDir not found:  ",opt$logDir))

# ----- Create datestamps ------------------------------------------------------

# All datestamps are UTC
timezone <- "UTC"

# Default to the current year
now <- lubridate::now(tzone = timezone)
if ( opt$datestamp == "" ) {
  opt$datestamp <- strftime(now, "%Y", tz = timezone)
}

# Handle the case where month or day is already specified
yearstamp <- as.numeric(stringr::str_sub(opt$datestamp, 1, 4))
startstamp <- paste0(yearstamp, "0101")
endstamp <- paste0((yearstamp+1), "0101")

logger.trace("Setting up data directories")
latestDataDir <- paste0(opt$archiveBaseDir, "/airsensor/latest")
yearDataDir <- paste0(opt$archiveBaseDir, "/airsensor/", yearstamp)

# ----- Set up logging ---------------------------------------------------------

logger.setup(
  traceLog = file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_DEBUG.log")), 
  infoLog  = file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_INFO.log")), 
  errorLog = file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_ERROR.log"))

# Silence other warning messages
options(warn=-1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createAirSensor_annual_exec.R version %s",VERSION)
sessionString <- paste(capture.output(sessionInfo()), collapse="\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ------ Create annual airsensor object ----------------------------------------

result <- try({
  
  latest7Path <- file.path(latestDataDir, paste0("airsensor_", opt$collectionName, "_latest7.rda"))
  yearPath <- file.path(yearDataDir, paste0("airsensor_", opt$collectionName, "_", yearstamp, ".rda"))
  # cur_monthPath <- file.path(cur_monthlyDir, paste0("airsensor_", opt$collectionName, "_", cur_monthStamp, ".rda"))
  # prev_monthPath <- file.path(prev_monthlyDir, paste0("airsensor_", opt$collectionName, "_", prev_monthStamp, ".rda"))
  
  # Load latest7
  if ( file.exists(latest7Path) ) {
    latest7 <- get(load(latest7Path))
  } else {
    logger.trace("Skipping %s, missing %s", opt$collectionName, latest7Path)
    next
  }
  
  # Conbine latest7 and year
  if ( file.exists(yearPath) ) {
    year <- get(load(yearPath))
    logger.trace("Joining latest7 and year")
    monitorIDs <- union(year$meta$monitorID, latest7$meta$monitorID)
    # TODO:  Remove this when PWFSLSmoke handles joining a monitor object with itself
    result <- try({
      airsensor <- PWFSLSmoke::monitor_join(year, latest7, monitorIDs) 
    }, silent = TRUE)
    if ( "try-error" %in% class(result) ) {
      err_msg <- geterrmessage()
      if ( stringr::str_detect(err_msg, "if (ncol(data) == 1) { : argument is of length zero") ) {
        # Ignore this one
      } else {
        stop(err_msg)
      }
    }
  } else {
    airsensor <- latest7 # default when starting from scratch
  }
  
  # Save the annual file
  filename <- paste0("airsensor_", opt$collectionName, "_", yearstamp, ".rda")
  filepath <- file.path(yearDataDir, filename)
  
  logger.info("Writing 'airsensor' data to %s", filename)
  save(list="airsensor", file = filepath)
  
}, silent=TRUE)

# Handle errors
if ( "try-error" %in% class(result) ) {
  msg <- paste("Error creating annual airsensor file: ", geterrmessage())
  logger.fatal(msg)
} else {
  # Guarantee that the errorLog exists
  if ( !file.exists(errorLog) ) 
    dummy <- file.create(errorLog)
  logger.info("Completed successfully!")
}
