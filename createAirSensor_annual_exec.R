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
  if ( !file.exists(yearPath) ) {

    airsensor <- latest7 # default when starting from scratch

  } else {
    
    # NOTE:  Don't use PWFSLSmoke::monitor_join(). (ver 1.2.103 has bugs)
    
    # TODO:  We have a basic problem with the pwfsl_closest~ variables.
    # TODO:  These can change whan a new, temprary monitor gets installed.
    # TODO:  We don't want to have two separate metadata records for a single 
    # TODO:  Sensor as the metadata is supposed to be location-specific and
    # TODO:  not time-dependent. Unfortunately, the location of the nearest
    # TODO:  PWFSL monitor is time-dependent and any choice we make will break
    # TODO:  things like pat_externalFit() for those periods when a temporary
    # TODO:  monitor is closer than a permanent monitor.
    # TODO:
    # TODO:  Ideally, enhanceSynopticData() would have some concept of
    # TODO:  "permanent" monitors but this is far beyond what is currently
    # TODO:  supported.
    
    year <- get(load(yearPath))

    # Update year_meta with mutable information
    year_meta <- year$meta
    for ( index_year in seq_len(nrow(year$meta)) ) {
      monitorID <- year_meta$monitorID[index_year]
      if ( monitorID %in% latest7$meta$monitorID ) {
        index_latest7 <- which(latest7$meta$monitorID == monitorID)
        year_meta$pwfsl_closestDistance[index_year] <-
          latest7$meta$pwfsl_closestDistance[index_latest7]
        year_meta$pwfsl_closestMonitorID[index_year] <-
          latest7$meta$pwfsl_closestMonitorID[index_latest7]
      }
    }

    #  Combine meta
    suppressMessages({
      meta <- dplyr::full_join(year_meta, latest7$meta, by = NULL)
    })
    
    # Strip off data overlap
    year_data <- 
      year$data %>%
      dplyr::filter(datetime < latest7$data$datetime[1])
    
    # Combine data
    suppressMessages({
      data <- 
        dplyr::full_join(year_data, latest7$data, by = NULL) %>%
        dplyr::arrange(datetime)
    })
    
    # Create an "airsensor" object
    airsensor <- list(
      meta = meta, 
      data = data
    )
    class(airsensor) <- c("airsensor", "ws_monitor", "list")
    
    # Guarante that the order of meta and data agree
    airsensor <- PWFSLSmoke::monitor_subset(airsensor)
    
    # Add "airsensor" class back again
    class(airsensor) <- union("airsensor", class(airsensor))
    
  } # END of file.exists(yearPath)
  
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
