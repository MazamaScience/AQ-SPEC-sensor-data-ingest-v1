#!/usr/local/bin/Rscript

# This Rscript will download the latest timeseries data from ThingSpeak and
# and use it to create pat_<id>_latest7.rda files.
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
  
  # Set API keys
  source("../global_vars.R")
  
  # RStudio session
  opt <- list(
    archiveBaseDir = file.path(getwd(), "data"),
    logDir = file.path(getwd(), "logs"),
    version = FALSE
  )
  
} else {
  
  # Set API keys
  source("./global_vars.R")
  
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
  cat(paste0("createPAT_latest_exec.R ",VERSION,"\n"))
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
  traceLog = file.path(opt$logDir, paste0("createPAT_latest_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createPAT_latest_DEBUG.log")), 
  infoLog  = file.path(opt$logDir, paste0("createPAT_latest_INFO.log")), 
  errorLog = file.path(opt$logDir, paste0("createPAT_latest_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createPAT_latest_ERROR.log"))

if ( interactive() ) {
  logger.setLevel(TRACE)
}

# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createPAT_latest_exec.R version %s",VERSION)
optString <- paste(capture.output(str(opt)), collapse = "\n")
logger.debug("Script options: \n\n%s\n", optString)
sessionString <- paste(capture.output(sessionInfo()), collapse = "\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ------ Create PAT objects ----------------------------------------------------

# Get times
tryCatch(
  expr = {
    endtime <- lubridate::now(tzone = "UTC")
    # NOTE:  We can only get 2 days of data per web request.
    # NOTE:  But 7 was standard in the previous version so we stick with that.
    starttime <- endtime - lubridate::ddays(7)
    
    # Get strings
    startdate <- strftime(starttime, "%Y-%m-%d %H:%M:%S", tz = "UTC")
    enddate <- strftime(endtime, "%Y-%m-%d %H:%M:%S", tz = "UTC")
    
    # Create the UTC YYYYmmdd stamp
    datestamp <- strftime(starttime, "%Y%m%d", tz = "UTC")
    monthstamp <- stringr::str_sub(datestamp, 1, 6)
    yearstamp <- stringr::str_sub(datestamp, 1, 4)
  },
  error = function(e) {
    msg <- paste('Error creating datetimes ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# Create directory if it doesn't exist
tryCatch(
  expr = {
    outputDir <- file.path(opt$archiveBaseDir, "pat", "latest")
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
    logger.info('Loading PAS data ...')
    pas <- pas_load()
  },
  error = function(e) {
    msg <- paste('Fatal PAS Load Execution: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

sensor_indices <- pas$sensor_index
logger.info("Loading PAT data for %d sensors", length(sensor_indices))

# Load PAT`
tryCatch(
  expr = {
    # Init counts
    successCount <- 0
    count <- 0
    
    for ( sensor_index in sensor_indices ) {
      
      # ++ count
      count <- count + 1
      
      deviceDeploymentID <- 
        pas %>%
        dplyr::filter(.data$sensor_index == !!sensor_index) %>%
        dplyr::pull(.data$deviceDeploymentID)
      
      # Load the PAT objects
      tryCatch(
        expr = {
          logger.debug(
            "%4d/%d pat_createNew(api_key, pas, '%s', '%s', '%s', 'UTC', 0)",
            count,
            length(sensor_indices),
            sensor_index,
            startdate,
            enddate
          )
          
          pat <- 
            pat_createNew(
              api_key = PURPLE_AIR_API_READ_KEY,
              pas = pas,
              sensor_index = sensor_index,
              startdate = startdate,
              enddate = enddate,
              timezone = "UTC",
              average = 0,
              verbose = FALSE
            )
          
          filename <- paste0("pat_", deviceDeploymentID, "_latest7.rda")
          tryCatch(
            expr = {
              filepath <- file.path(outputDir, filename)
              logger.trace("Writing PAT data to %s", filename)
              save(pat, file = filepath)
            },
            error = function(e) {
              # NOTE: Throwing a `stop` here will yield a warning to the
              # NOTE: enclosing tryCatch
              msg <- paste('Failed to write ', filename, ': ', e)
              logger.fatal(msg)
              stop(msg)
            }
          )
          # Count if no errors occur
          successCount <- successCount + 1
        },
        error = function(e) {
          # Log the failed PAT load and move on
          logger.warn(e)
        }
      )
    }
    
  },
  error = function(e) {
    msg <- paste("Error creating latest PAT file: ", e)
    logger.fatal(msg)
  },
  finally = {
    # End Log info
    logger.info("%d PAT files were generated.", successCount)
    logger.info("Completed successfully!")
    # Guarantee that the errorLog exists
    if ( !file.exists(errorLog) ) {
      dummy <- file.create(errorLog)
    }
  }
)
