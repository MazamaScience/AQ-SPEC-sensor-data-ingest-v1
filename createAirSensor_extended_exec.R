#!/usr/local/bin/Rscript

# This Rscript will ingest airsensor_<id>_latest7.rda files and use them to
# create airsensor files with extended time ranges: 45-day and monthly.
#
# See test/Makefile for testing options
#

#  ----- . AirSensor 1.1.x . first pass
VERSION = "0.3.0"

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
    collectionName = "scaqmd",
    version = FALSE
  )  
  
} else {
  
  option_list <- list(
    optparse::make_option(
      c("-o","--archiveBaseDir"), 
      default = getwd(), 
      help = "Output base directory for generated .RData files [default = \"%default\"]"
    ),
    optparse::make_option(
      c("-l","--logDir"), 
      default = getwd(), 
      help = "Output directory for generated .log file [default = \"%default\"]"
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
  cat(paste0("createAirSensor_extended_exec.R ",VERSION,"\n"))
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

# ----- Set up logging ---------------------------------------------------------

logger.setup(
  traceLog = file.path(opt$logDir, paste0("createAirSensor_extended_",opt$collectionName,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createAirSensor_extended_",opt$collectionName,"_DEBUG.log")), 
  infoLog  = file.path(opt$logDir, paste0("createAirSensor_extended_",opt$collectionName,"_INFO.log")), 
  errorLog = file.path(opt$logDir, paste0("createAirSensor_extended_",opt$collectionName,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createAirSensor_extended_",opt$collectionName,"_ERROR.log"))

if ( interactive() ) {
  logger.setLevel(TRACE)
}

# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createAirSensor_extended_exec.R version %s",VERSION)
optString <- paste(capture.output(str(opt)), collapse = "\n")
logger.debug("Script options: \n\n%s\n", optString)
sessionString <- paste(capture.output(sessionInfo()), collapse = "\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ------ Get labels ------------------------------------------------------------

tryCatch(
  expr = {
    # All datestamps are UTC
    timezone <- "UTC"
    
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
    latestDataDir <- paste0(opt$archiveBaseDir, "/airsensor/latest")
    cur_monthlyDir <- paste0(opt$archiveBaseDir, "/airsensor/", cur_yearStamp)
    prev_monthlyDir <- paste0(opt$archiveBaseDir, "/airsensor/", prev_yearStamp)
    
    logger.trace("latestDataDir = %s", latestDataDir)
    logger.trace("cur_monthlyDir = %s", cur_monthlyDir)
    logger.trace("prev_monthlyDir = %s", prev_monthlyDir)
    
    if ( !dir.exists(cur_monthlyDir) )
      dir.create(cur_monthlyDir, showWarnings = FALSE, recursive = TRUE)
    
    if ( !dir.exists(prev_monthlyDir) )
      dir.create(prev_monthlyDir, showWarnings = FALSE, recursive = TRUE)
  },
  error = function(e) {
    msg <- paste("Error in PAS file: ", e)
    logger.fatal(msg)
    stop(msg)
  }
)

# ------ Create 45-day airsensor objects ---------------------------------------

tryCatch(
  expr = {
    
    latest7Path <- file.path(latestDataDir, paste0("airsensor_", opt$collectionName, "_latest7.rda"))
    latest45Path <- file.path(latestDataDir, paste0("airsensor_", opt$collectionName, "_latest45.rda"))
    cur_monthPath <- file.path(cur_monthlyDir, paste0("airsensor_", opt$collectionName, "_", cur_monthStamp, ".rda"))
    prev_monthPath <- file.path(prev_monthlyDir, paste0("airsensor_", opt$collectionName, "_", prev_monthStamp, ".rda"))
    
    logger.trace("Loading %s", latest7Path)
    
    # Load latest7
    if ( file.exists(latest7Path) ) {
      latest7 <- get(load(latest7Path))
    } else {
      logger.trace("Skipping %s, missing %s", opt$collectionName, latest7Path)
      next
    }
    
    # Combine latest7 and latest45
    if ( file.exists(latest45Path) ) {
      
      logger.trace("Loading %s", latest45Path)
      latest45 <- get(load(latest45Path))
      logger.trace("Joining latest7 and latest45")
      monitorIDs <- union(latest45$meta$monitorID, latest7$meta$monitorID)
      logger.trace("monitorIDs = %s", paste0(monitorIDs, collapse = ", "))
      # Handle erros by just defaulting to latest7
      result <- try({
        airsensor_full <- sensor_join(latest45, latest7) 
      }, silent = TRUE)
      if ( "try-error" %in% class(result) ) {
        airsensor_full <- latest7
      }
      
    } else {
      
      airsensor_full <- latest7 # default when starting from scratch
      
    }
    
    # Save latest 45 sensor data
    tryCatch(
      expr = {
        airsensor <- 
          airsensor_full %>%
          sensor_filterDatetime(
            startdate = now_m45, 
            enddate = now,
            timezone = timezone 
          )

        logger.trace("Update and save %s", latest45Path)
        
        save(list = "airsensor", file = latest45Path)
      }, 
      error = function(e) {
        # Catch errors one level up 
        stop(e)
      }
    )
    
    # Save current month data
    tryCatch(
      expr = {
        airsensor <- 
          airsensor_full %>%
          sensor_filterDate(
            startdate = cur_monthStart, 
            enddate = cur_monthEnd,
            timezone = timezone
          )
        
        logger.trace("Update and save %s", cur_monthPath)
        
        save(list = "airsensor", file = cur_monthPath)
      }, 
      error = function(e) {
        # Catch errors up one level 
        stop(e)
      }
    )
    
  }, 
  error = function(e) {
    msg <- paste("Airsensor creation error: ", e)
    logger.fatal(msg)
  }
)

# Save previous month

# ------ Create 45-day airsensor objects ---------------------------------------

tryCatch(
  expr = {
    
    if ( lubridate::day(now) < 7 ) {
      logger.trace("Update and save %s", prev_monthPath)
      airsensor <- 
        airsensor_full %>%
        sensor_filterDate(
          startdate = prev_monthStart, 
          enddate = prev_monthEnd,
          timezone = "UTC"
        )
      
      save(list = "airsensor", file = prev_monthPath)
    }
 
  }, 
  error = function(e) {
    msg <- paste("Error creating previous month file: ", e)
    logger.warn(msg)
  }
)


# Guarantee that the errorLog exists
if ( !file.exists(errorLog) ) dummy <- file.create(errorLog)
logger.info("Completed successfully!")


