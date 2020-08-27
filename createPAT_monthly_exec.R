#!/usr/local/bin/Rscript

# This Rscript will download a month's worth timeseries data from ThingSpeak and
# use it to create pat_<id>_<monthstamp>.rda files.
#
# See test/Makefile for testing options
#

#  ----- . AirSensor 0.9.x . minor restructure
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
    archiveBaseDir = file.path(getwd(), "test/output"),
    logDir = file.path(getwd(), "test/logs"),
    countryCode = "US",
    stateCode = "CA",
    pattern = "^[Ss][Cc].._..$",
    datestamp = "201909",
    version = FALSE
  )

} else {

  # Set up OptionParser
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
      c("-d","--datestamp"),
      default = "201907",
      help = "Datestamp specifying the year and month as YYYYMM [default = current month]"
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
  cat(paste0("createPAT_monthly_exec.R ",VERSION,"\n"))
  quit()
}

# ----- Validate parameters ----------------------------------------------------

timezone <- "UTC"

MazamaCoreUtils::stopIfNull(opt$countryCode)

if ( dir.exists(opt$archiveBaseDir) ) {
  setArchiveBaseDir(opt$archiveBaseDir)
} else {
  stop(paste0("archiveBaseDir not found:  ", opt$archiveBaseDir))
}

if ( !dir.exists(opt$logDir) )
  stop(paste0("logDir not found:  ", opt$logDir))

# Default to the current month
if ( opt$datestamp == "" ) {
  now <- lubridate::now(tzone = timezone)
  opt$datestamp <- strftime(now, "%Y%m01", tz = timezone)
}

# Handle the case where the day is already specified
datestamp <- stringr::str_sub(paste0(opt$datestamp,"01"), 1, 8)
monthstamp <- stringr::str_sub(datestamp, 1, 6)
yearstamp <- stringr::str_sub(datestamp, 1, 4)

mmstamp <- stringr::str_sub(monthstamp, 5, 6)

# ----- Set up logging ---------------------------------------------------------

# Assign region ID to SCAQMD
regionID <- 'SCAQMD'
# if ( is.null(opt$stateCode) ) {
#   regionID <- opt$countryCode
# } else {
#   regionID <- paste0(opt$countryCode, ".", opt$stateCode)
# }


logger.setup(
  traceLog = file.path(opt$logDir, paste0("createPAT_monthly_",regionID,"_",monthstamp,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createPAT_monthly_",regionID,"_",monthstamp,"_DEBUG.log")),
  infoLog  = file.path(opt$logDir, paste0("createPAT_monthly_",regionID,"_",monthstamp,"_INFO.log")),
  errorLog = file.path(opt$logDir, paste0("createPAT_monthly_",regionID,"_",monthstamp,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createPAT_monthly_",regionID,"_",monthstamp,"_ERROR.log"))

if ( interactive() ) {
  logger.setLevel(TRACE)
}

# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createPAT_monthly_exec.R version %s",VERSION)
optString <- paste(capture.output(str(opt)), collapse = "\n")
logger.debug("Script options: \n\n%s\n", optString)
sessionString <- paste(capture.output(sessionInfo()), collapse = "\n")
logger.debug("R session:\n\n%s\n", sessionString)


# ------ Get timestamps --------------------------------------------------------

# NOTE:  Get times that extend one day earlier and one day later to ensure we get
# NOTE:  have a least a full month, regardless of timezone. This overlap is OK
# NOTE:  because the pat_join() function uses pat_distinct() to remove duplicate
# NOTE:  records.

tryCatch(
  expr = {
    starttime <- MazamaCoreUtils::parseDatetime(datestamp, timezone = timezone)
    endtime <- lubridate::ceiling_date(starttime + lubridate::ddays(20), unit = "month")

    starttime <- starttime - lubridate::ddays(1)
    endtime <- endtime + lubridate::ddays(1)

    # Get strings
    startdate <- strftime(starttime, "%Y%m%d", tz = timezone)
    enddate <- strftime(endtime, "%Y%m%d", tz = timezone)

    logger.trace("startdate = %s, enddate = %s", startdate, enddate)
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
    outputDir <- file.path(opt$archiveBaseDir, "pat", yearstamp, '/', mmstamp)
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

# ------ Load PAS object -------------------------------------------------------

# Load PAS object
tryCatch(
  expr = {
    logger.info('Loading PAS data ...')
    pas <- 
      pas_load(archival = TRUE) %>%
      pas_filter(.data$countryCode == opt$countryCode) %>%
      pas_filter(.data$lastSeenDate > starttime)
  },
  error = function(e) {
    msg <- paste('Fatal PAS Load Execution: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

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
  
    logger.info("Loading PAT data for %d sensors", length(deviceDeploymentIDs))
  },
  error = function(e) {
    msg <- paste('deviceDeploymentID not found: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# ------ Create PAT objects ----------------------------------------------------

# Load PAT
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
            "%4d/%d pat_createNew(id = '%s', label = NULL, pas = pas, startdate = '%s', enddate = '%s')",
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

          filename <- paste0("pat_", deviceDeploymentID, "_", monthstamp, ".rda")
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
    msg <- paste("Error creating monthly PAT file: ", e)
    logger.fatal(msg)
  },
  finally = {
    # End Log info
    logger.info("%d monthly PAT files were generated.", successCount)
    logger.info("Completed successfully!")
    # Guarantee that the errorLog exists
    if ( !file.exists(errorLog) ) {
      dummy <- file.create(errorLog)
    }
  }
)
