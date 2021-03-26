#!/usr/local/bin/Rscript

# This Rscript will ingest airsensor_~_latest7.rda files and use them to create
# airsensor files for an entire year.
#
# See test/Makefile for testing options
#

#  ----- . AirSensor 0.9.x . fix NAs with logical type
VERSION = "0.2.7"

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
      help = "Output directory for generated .log file [default=\"%default\"]"
    ),
    optparse::make_option(
      c("-n","--collectionName"), 
      default = "scaqmd", 
      help = "Name associated with this collection of sensors [default=\"%default\"]"
    ),
    optparse::make_option(
      c("-V","--version"), 
      action = "store_true", 
      default = FALSE, 
      help = "Print out version number [default=\"%default\"]"
    )
  )
  
  # Parse arguments
  opt <- optparse::parse_args(optparse::OptionParser(option_list = option_list))
  
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

# ----- Set up logging ---------------------------------------------------------

logger.setup(
  traceLog = file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_DEBUG.log")), 
  infoLog  = file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_INFO.log")), 
  errorLog = file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createAirSensor_annual_",opt$collectionName,"_ERROR.log"))

if ( interactive() ) {
  logger.setLevel(TRACE)
}

# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createAirSensor_annual_exec.R version %s",VERSION)
optString <- paste(capture.output(str(opt)), collapse = "\n")
logger.debug("Script options: \n\n%s\n", optString)
sessionString <- paste(capture.output(sessionInfo()), collapse = "\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ----- Create datestamps ------------------------------------------------------

# All datestamps are UTC
timezone <- "UTC"

# Use the the current year and extend by a day to capture all timezones
yearstamp <- lubridate::year(lubridate::now(tzone = timezone))
startstamp <- paste0(yearstamp - 1, "1231")
endstamp <- paste0((yearstamp + 1), "0102")

logger.trace("Setting up data directories")
latestDataDir <- paste0(opt$archiveBaseDir, "/airsensor/latest")
yearDataDir <- paste0(opt$archiveBaseDir, "/airsensor/", yearstamp)

# ------ Create annual airsensor object ----------------------------------------

# Create paths
tryCatch(
  expr = {
    
    latest7Path <- file.path(latestDataDir, paste0("airsensor_", opt$collectionName, "_latest7.rda"))
    yearPath <- file.path(yearDataDir, paste0("airsensor_", opt$collectionName, "_", yearstamp, ".rda"))

    logger.trace("Loading %s", latest7Path)
    
    # Load latest7
    if ( file.exists(latest7Path) ) {
      latest7 <- get(load(latest7Path))
    } else {
      err_msg <- paste0("Missing ", latest7Path)
      logger.error(err_msg)
      stop(err_msg)
    }
    
  }, 
  error = function(e) {
    msg <- paste("Error loading paths: ", e) 
    logger.fatal(msg)
    stop(msg)
  }
)

# Load airsensor files
tryCatch(
  expr = {
    if ( file.exists(yearPath) ) {
      
      # TODO:  We have a basic problem with the pwfsl_closest~ variables.
      # TODO:  These can change when a new, temprary monitor gets installed.
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
      
      logger.trace("Loading %s", yearPath)
      year <- get(load(yearPath))
      
      # Update year_meta with mutable information
      year_meta <- year$meta
      for ( index_year in seq_len(nrow(year$meta)) ) {
        
        monitorID <- year_meta$monitorID[index_year]
        logger.trace("Updating pwfsl_closestMonitorID for %s", monitorID)
        
        if ( monitorID %in% latest7$meta$monitorID ) {
          
          index_latest7 <- which(latest7$meta$monitorID == monitorID)
          year_meta$pwfsl_closestDistance[index_year] <-
            latest7$meta$pwfsl_closestDistance[index_latest7]
          year_meta$pwfsl_closestMonitorID[index_year] <-
            latest7$meta$pwfsl_closestMonitorID[index_latest7]
          
        }
        
      }
      
      # NOTE:  If a latest7 file is created with no data, all of the metadata
      # NOTE:  fields with missing data will be of type "logical". This will 
      # NOTE:  prevent them from being merged with metadata fields of type 
      # NOTE:  character. Here we ensure that everything has the proper type.
      
      logger.trace("Correcting potential 'logical' types in metadata")
      
      latest7_meta <-
        latest7$meta %>%
        dplyr::mutate_if(is.logical, as.character) %>%
        dplyr::mutate_at(
          vars(longitude, latitude, elevation, pwfsl_closestDistance),
          as.numeric
        )
      
      year_meta <-
        year_meta %>%
        dplyr::mutate_if(is.logical, as.character) %>%
        dplyr::mutate_at(
          vars(longitude, latitude, elevation, pwfsl_closestDistance),
          as.numeric
        )
      
      logger.trace("Combining metadata")
      
      # < NOTE:  Despite the efforts above, if a sensor has a new *location* there >
      # < NOTE:  is nothing we can do to avoid duplicates. So we have to filter for >
      # < NOTE:  uniqueness at this point as having duplicate monitorIDs in the > 
      # < NOTE:  meta dataframe breaks the data model. >
      
      # NOTE:  As of AirSensor 0.8.x, this should no longer be a problem because
      # NOTE:  the 'monitorID' is a truly unique 'deviceDeploymentID'. But we
      # NOTE:  leave this here because it doesn't hurt anything.
      
      #  Combine meta
      suppressMessages({
        meta <- 
          # Join the latest and yearly meta in that order to keep newer locations 
          dplyr::full_join(latest7_meta, year_meta, by = NULL) %>%
          # Remove rows with duplicate monitorID which we use as a unique identifier
          dplyr::distinct(monitorID, .keep_all = TRUE)
        
      })
      
      logger.trace("Datetime filtering")
      
      # Strip off data overlap
      year_data <- 
        year$data %>%
        dplyr::filter(datetime < latest7$data$datetime[1])
      
      logger.trace("Combining data")
      
      # Combine data
      suppressMessages({
        data <- 
          dplyr::full_join(year_data, latest7$data, by = NULL) %>%
          dplyr::arrange(datetime)
      })
      
      logger.trace("Create airsensor object")
      
      logger.trace("meta$monitorID = %s", paste0(meta$monitorID, collapse = ", "))
      logger.trace("names(data) = %s", paste0(names(data), collapse = ", "))
      
      # Create an "airsensor" object
      airsensor <- list(
        meta = meta, 
        data = data
      )
      class(airsensor) <- c("airsensor", "ws_monitor", "list")
      
      logger.trace("Calling PWFSLSmoke::monitor_subset(airsensor)")
      
      # Guarante that the order of meta and data agree
      airsensor <- PWFSLSmoke::monitor_subset(airsensor)
      
      # Add "airsensor" class back again
      class(airsensor) <- union("airsensor", class(airsensor))
      
      logger.trace("Successfully built the annual airsensor")
      
    } else {
      
      logger.trace("No annual file found. Using latest7.")
      airsensor <- latest7 # default when starting from scratch
      
    } 
    
  }, 
  error = function(e) {
    msg <- paste("Error creating annual airsensor file: ", e)
    logger.fatal(msg)
  }
  
)

# ----- Save annual data -------------------------------------------------------
tryCatch(
  expr = {
    logger.trace("Trim and save %s", yearPath)
    # Trim to year boundaries
    airsensor <- 
      PWFSLSmoke::monitor_subset(airsensor, tlim = c(startstamp, endstamp))
    save(list = "airsensor", file = yearPath)
  }, 
  error = function(e) {
    msg <- paste("Error saving annual airsensor file: ", e)
    logger.fatal(msg)
    stop(e)
  }
)

if ( !file.exists(errorLog) ) 
  dummy <- file.create(errorLog)
logger.info("Completed successfully!")

