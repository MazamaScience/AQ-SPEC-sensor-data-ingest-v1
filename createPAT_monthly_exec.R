#!/usr/local/bin/Rscript

# This Rscript will download a month's worth timeseries data from ThingSpeak and
# use it to create pat_<id>_<monthstamp>.rda files.
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
    datestamp = "201710",
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

# Assign region ID
regionID <- 'scaqmd'

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

tryCatch(
  expr = {
    # SCAQMD Database
    logger.info('Loading PAS data ...')
    pas <- pas_load(
      datestamp = NULL, # TODO:  Use datestamp after enough PAS files have been generated
      retries = 32,
      timezone = "UTC",
      archival = TRUE,
      verbose = FALSE
    )
  },
  error = function(e) {
    msg <- paste('Fatal PAS load Execution: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

sensor_indices <- pas$sensor_index
logger.info("Loading PAT data for %d sensors", length(sensor_indices))

# ------ Create PAT objects ----------------------------------------------------

# Load PAT
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
