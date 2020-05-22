#!/usr/local/bin/Rscript

# This Rscript will download the latest timeseries data from Purple Air.
#
# See test/Makefile for testing options
#

#  ----- . AirSensor 0.8.x . -----
VERSION = "0.2.5"

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
    countryCode = "US",
    stateCode = "CA",
    pattern = "^[Ss][Cc].._..$",
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
      c("-c","--countryCode"), 
      default = "US", 
      help = "Two character countryCode used to subset sensors [default = \"%default\"]"
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

# Command line options
optionsString <- paste(capture.output(str(opt)), collapse='\n')
logger.debug('Command line options:\n\n%s\n', optionsString)

# ----- Validate parameters ----------------------------------------------------

MazamaCoreUtils::stopIfNull(opt$countryCode)

if ( dir.exists(opt$archiveBaseDir) ) {
  setArchiveBaseDir(opt$archiveBaseDir)
} else {
  stop(paste0("archiveBaseDir not found:  ",opt$archiveBaseDir))
}

if ( !dir.exists(opt$logDir) )
  stop(paste0("logDir not found:  ",opt$logDir))

# ----- Set up logging ---------------------------------------------------------

if ( is.null(opt$stateCode) ) {
  regionID <- opt$countryCode
} else {
  regionID <- paste0(opt$countryCode, ".", opt$stateCode)
}

logger.setup(
  traceLog = file.path(opt$logDir, paste0("createPAT_latest_",regionID,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createPAT_latest_",regionID,"_DEBUG.log")), 
  infoLog  = file.path(opt$logDir, paste0("createPAT_latest_",regionID,"_INFO.log")), 
  errorLog = file.path(opt$logDir, paste0("createPAT_latest_",regionID,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createPAT_latest_",regionID,"_ERROR.log"))

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
    # TODO:  Can we ask for 7+ days without triggering multiple web requests?
    # starttime <- lubridate::floor_date(endtime, unit = "day") - lubridate::ddays(7)
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
    pas <-
      pas_load() %>%
      pas_filter(.data$countryCode == opt$countryCode)
  },
  error = function(e) {
    msg <- paste('Fatal PAS Load Execution: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# Subset by state if reqeusted
if ( !is.null(opt$stateCode) )
  pas <- pas_filter(pas, .data$stateCode == opt$stateCode)
  
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

logger.info("Loading PAT data for %d sensors", length(deviceDeploymentIDs))

# Load PAT`
tryCatch(
  expr = {
    # Init counts
    successCount <- 0
    count <- 0

    for ( deviceDeploymentID in deviceDeploymentIDs ) {
      
      # ++ count
      count <- count + 1

      # Load the PAT objects
      tryCatch(
        expr = {
          logger.debug(
            "%4d/%d pat_createNew(id = '%s', label = NULL, pas = pas, '%s', '%s')",
            count,
            length(deviceDeploymentIDs),
            deviceDeploymentID,
            startdate,
            enddate
          )

          # Load via ThingSpeak API JSON
          pat <- pat_createNew(
            id = deviceDeploymentID,
            label = NULL,
            pas = pas,
            startdate = startdate,
            enddate = enddate,
            timezone = "UTC",
            baseUrl = "https://api.thingspeak.com/channels/"
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
