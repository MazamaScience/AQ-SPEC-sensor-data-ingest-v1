#!/usr/local/bin/Rscript

# This Rscript will download a month's worth timeseries data from Purple Air. 
#
# See test/Makefile for testing options
#

#  ----- . ----- . scaqmd version
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
    archiveBaseDir = file.path(getwd(), "output"),
    logDir = file.path(getwd(), "logs"),
    stateCode = "CA",
    pattern = "^[Ss][Cc].._..$",
    datestamp = "201909",
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
      c("-d","--datestamp"), 
      default = "201907", 
      help = "Datestamp specifying the year and month as YYYYMM [default = current month]"
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
  cat(paste0("createPAT_latest_exec.R ",VERSION,"\n"))
  quit()
}

# ----- Validate parameters ----------------------------------------------------

# All datestamps are UTC
timezone <- "UTC"

if ( dir.exists(opt$archiveBaseDir) ) {
  setArchiveBaseDir(opt$archiveBaseDir)
} else {
  stop(paste0("archiveBaseDir not found:  ", opt$archiveBaseDir))
}

if ( !dir.exists(opt$logDir) ) 
  stop(paste0("logDir not found:  ", opt$logDir))

# Default to the current month
now <- lubridate::now(tzone = timezone)
if ( opt$datestamp == "" ) {
  opt$datestamp <- strftime(now, "%Y%m01", tz = timezone)
}

# Handle the case where the day is already specified
datestamp <- stringr::str_sub(paste0(opt$datestamp,"01"), 1, 8)
monthstamp <- stringr::str_sub(datestamp, 1, 6)
yearstamp <- stringr::str_sub(datestamp, 1, 4)

# ----- Set up logging ---------------------------------------------------------

logger.setup(
  traceLog = file.path(opt$logDir, paste0("createPAT_monthly_",opt$stateCode,"_",monthstamp,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createPAT_monthly_",opt$stateCode,"_",monthstamp,"_DEBUG.log")), 
  infoLog  = file.path(opt$logDir, paste0("createPAT_monthly_",opt$stateCode,"_",monthstamp,"_INFO.log")), 
  errorLog = file.path(opt$logDir, paste0("createPAT_monthly_",opt$stateCode,"_",monthstamp,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createPAT_monthly_",opt$stateCode,"_",monthstamp,"_ERROR.log"))

if ( interactive() ) {
  logger.setLevel(TRACE)
}

# Silence other warning messages
options(warn=-1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createPAT_monthly_exec.R version %s",VERSION)
sessionString <- paste(capture.output(sessionInfo()), collapse="\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ------ Create PAT objects ----------------------------------------------------

result <- try({
  
  # Get times that extend one day earlier and one day later to ensure we get
  # have a least a full month, regardless of timezone. This overlap is OK 
  # because the pat_join() function uses pat_distinct() to remove duplicate 
  # records.
  
  starttime <- MazamaCoreUtils::parseDatetime(datestamp, timezone = timezone)
  endtime <- lubridate::ceiling_date(starttime + lubridate::ddays(20), unit="month")
  
  starttime <- starttime - lubridate::ddays(1)
  endtime <- endtime + lubridate::ddays(1)
  
  # Get strings
  startdate <- strftime(starttime, "%Y%m%d", tz = timezone)
  enddate <- strftime(endtime, "%Y%m%d", tz = timezone)
  
  logger.trace("startdate = %s, enddate = %s", startdate, enddate)
  
  # Create directory if it doesn't exist
  outputDir <- file.path(opt$archiveBaseDir, "pat", yearstamp)
  if ( !dir.exists(outputDir) ) {
    dir.create(outputDir, recursive = TRUE)
  }
  logger.info("Output directory: %s", outputDir)
  
  logger.info("Loading PAS data, archival = TRUE")
  pas <- pas_load(archival = TRUE) %>%
    pas_filter(lastSeenDate > starttime)
  
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
  
  for ( i in seq_along(labels) ) {
    
    # Try block so we keep chugging if one sensor fails
    result <- try({
      
      logger.debug("pat_createNew(pas, '%s', '%s', '%s')", 
                   labels[i], startdate, enddate)

      pat <- pat_createNew(
        pas,
        labels[i],
        startdate = startdate,
        enddate = enddate,
        timezone = "UTC",
        baseURL = "https://api.thingspeak.com/channels/"
      )
      
      filename <- paste0("pat_", R_labels[i], "_", monthstamp, ".rda")
      filepath <- file.path(outputDir, filename)
      
      logger.trace("Writing PAT data to %s", filename)
      save(list="pat", file=filepath)
      
    }, silent = TRUE)
    if ( "try-error" %in% class(result) ) {
      logger.warn(geterrmessage())
    }
    
  }  
  
}, silent=TRUE)

# Handle errors
if ( "try-error" %in% class(result) ) {
  msg <- paste("Error creating latest PAT file: ", geterrmessage())
  logger.fatal(msg)
} else {
  # Guarantee that the errorLog exists
  if ( !file.exists(errorLog) ) dummy <- file.create(errorLog)
  logger.info("Completed successfully!")
}

