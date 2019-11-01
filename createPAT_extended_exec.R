#!/usr/local/bin/Rscript

# This Rscript will ingest pat_~_latest7.rda files and use them to create pat
# files with extended time ranges: 45-day and monthly.
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
      help = "String patter passed to stringr::str_detect  [default = \"%default\"]"
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
  cat(paste0("createPAT_extended_exec.R ",VERSION,"\n"))
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
  traceLog = file.path(opt$logDir, paste0("createPAT_extended_",opt$stateCode,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createPAT_extended_",opt$stateCode,"_DEBUG.log")), 
  infoLog  = file.path(opt$logDir, paste0("createPAT_extended_",opt$stateCode,"_INFO.log")), 
  errorLog = file.path(opt$logDir, paste0("createPAT_extended_",opt$stateCode,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createPAT_extended_",opt$stateCode,"_ERROR.log"))

# Silence other warning messages
options(warn=-1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createPAT_extended_exec.R version %s",VERSION)
sessionString <- paste(capture.output(sessionInfo()), collapse="\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ------ Get timestamps --------------------------------------------------------

# All datestamps are UTC
timezone <- "UTC"

result <- try({
  
  logger.info("Loading PA Synoptic data, archival = TRUE")
  pas <- pas_load(archival = TRUE)
  
  # Find the labels of interest, only one per sensor
  labels <-
    pas %>%
    pas_filter(is.na(parentID)) %>%
    pas_filter(DEVICE_LOCATIONTYPE == "outside") %>%
    pas_filter(stateCode == opt$stateCode) %>%
    pas_filter(stringr::str_detect(label, opt$pattern)) %>%
    dplyr::pull(label) %>%
    make.names()
  
  logger.info("Working with PA Timeseries data for %d sensors", length(labels))

  # Get dates and date stamps
  now <- lubridate::now(tzone = timezone)
  now_m45 <- now - lubridate::ddays(45)
  cur_monthStart <- lubridate::floor_date(now, "month") - lubridate::ddays(1)
  cur_monthEnd <- lubridate::ceiling_date(now, "month") + lubridate::ddays(1)
  cur_monthStamp <- strftime(now, "%Y%m", tz = timezone)
  prev_midMonth <- cur_monthStart - lubridate::ddays(14)
  prev_monthStart <- lubridate::floor_date(prev_midMonth, "month") - lubridate::ddays(1)
  prev_monthEnd <- lubridate::ceiling_date(prev_midMonth, "month") + lubridate::ddays(1)
  prev_monthStamp <- strftime(prev_midMonth, "%Y%m", tz = timezone)
  cur_yearStamp <- strftime(now, "%Y", tz = timezone)
  prev_yearStamp <- strftime(prev_midMonth, "%Y", tz = timezone)
  
  logger.trace("Setting up data directories")
  latestDataDir <- paste0(opt$archiveBaseDir, "/pat/latest")
  cur_monthlyDir <- paste0(opt$archiveBaseDir, "/pat/", cur_yearStamp)
  prev_monthlyDir <- paste0(opt$archiveBaseDir, "/pat/", prev_yearStamp)
  
  logger.trace("latestDataDir = %s", latestDataDir)
  logger.trace("cur_monthlyDir = %s", cur_monthlyDir)
  logger.trace("prev_monthlyDir = %s", prev_monthlyDir)
  
  if ( !dir.exists(cur_monthlyDir) )
    dir.create(cur_monthlyDir, showWarnings = FALSE, recursive = TRUE)
  
  if ( !dir.exists(prev_monthlyDir) )
    dir.create(prev_monthlyDir, showWarnings = FALSE, recursive = TRUE)
  
}, silent=TRUE)

# Handle errors
if ( "try-error" %in% class(result) ) {
  msg <- paste("Error in PAS file: ", geterrmessage())
  logger.fatal(msg)
  stop(msg)
}

# ------ Create 45-day PAT objects ---------------------------------------------

result <- try({
  
  for ( label in labels ) {
    
    # Try block so we keep chugging if one sensor fails
    result <- try({

      latest7Path <- file.path(latestDataDir, paste0("pat_", label, "_latest7.rda"))
      latest45Path <- file.path(latestDataDir, paste0("pat_", label, "_latest45.rda"))
      cur_monthPath <- file.path(cur_monthlyDir, paste0("pat_", label, "_", cur_monthStamp, ".rda"))
      prev_monthPath <- file.path(prev_monthlyDir, paste0("pat_", label, "_", prev_monthStamp, ".rda"))
      
      # Load latest7
      if ( file.exists(latest7Path) ) {
        latest7 <- get(load(latest7Path))
      } else {
        logger.trace("Skipping %s, missing %s", label, latest7Path)
        next
      }
      
      # Load latest45
      if ( file.exists(latest45Path) ) {
        latest45 <- get(load(latest45Path))
      } else {
        latest45 <- latest7 # default when starting from scratch
      }
      
      logger.trace("Updating %s", latest45Path)
      
      # NOTE:  PWFSL monitors may come and go so the pwfsl_closest~ data might
      # NOTE:  be different in latest7 and latest45. We update the latest45
      # NOTE:  record to always use the latest7$pwfsl_closest~ data so that 
      # NOTE:  pat_join() doesn't fail with:
      # NOTE:    "`pat` objects must be of the same monitor"
      
      latest45$meta$pwfsl_closestMonitorID <- latest7$meta$pwfsl_closestMonitorID
      latest45$meta$pwfsl_closestDistance <- latest7$meta$pwfsl_closestDistance
      
      # Join
      pat_full <- AirSensor::pat_join(latest45, latest7) 
      
      # Update the latest45 file
      pat <- 
        pat_full %>%
        pat_filterDate(now_m45, now, timezone = latest7$meta$timezone[1])
        
      save(list="pat", file = latest45Path)
      
      # Update the current month file
      pat <- 
        pat_full %>%
        pat_filterDate(cur_monthStart, cur_monthEnd, timezone = timezone)
      
      save(list="pat", file = cur_monthPath)
      
      # Update the previous month file until 7-days into the current month
      if ( lubridate::day(now) < 7 ) {
        pat <- 
          pat_full %>%
          pat_filterDate(prev_monthStart, prev_monthEnd, timezone = timezone)
        
        save(list="pat", file = prev_monthPath)
      }
      
    }, silent = TRUE)
    if ( "try-error" %in% class(result) ) {
      logger.warn(geterrmessage())
    }
    
  }  
  
}, silent=TRUE)

# Handle errors
if ( "try-error" %in% class(result) ) {
  msg <- paste("Error creating monthly PAT file: ", geterrmessage())
  logger.fatal(msg)
} else {
  # Guarantee that the errorLog exists
  if ( !file.exists(errorLog) ) dummy <- file.create(errorLog)
  logger.info("Completed successfully!")
}

