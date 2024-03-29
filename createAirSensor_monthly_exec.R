#!/usr/local/bin/Rscript

# This Rscript will process archived 'pat' data files into a single 'airsensor'
# airsensor_<collection-id>_<monthstamp>.rda file containing houlry aggregated
# pm25 data for all sensors.
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
    archiveBaseDir = file.path(getwd(), "output"),
    logDir = file.path(getwd(), "logs"),
    collectionName = "scaqmd",
    datestamp = "201710",
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
      c("-n","--collectionName"), 
      default = "scaqmd", 
      help = "Name associated with this collection of sensors [default = \"%default\"]"
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
  cat(paste0("createAirSensor_monthly_exec.R ",VERSION,"\n"))
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

# Assign the regionID
regionID <- opt$collectionName

logger.setup(
  traceLog = file.path(opt$logDir, paste0("createAirSensor_monthly_",regionID,"_",monthstamp,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createAirSensor_monthly_",regionID,"_",monthstamp,"_DEBUG.log")),
  infoLog  = file.path(opt$logDir, paste0("createAirSensor_monthly_",regionID,"_",monthstamp,"_INFO.log")),
  errorLog = file.path(opt$logDir, paste0("createAirSensor_monthly_",regionID,"_",monthstamp,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createAirSensor_monthly_",regionID,"_",monthstamp,"_ERROR.log"))

if ( interactive() ) {
  logger.setLevel(TRACE)
}

# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createAirSensor_monthly_exec.R version %s",VERSION)
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
    outputDir <- file.path(opt$archiveBaseDir, "airsensor", yearstamp)
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

# Capture Unique IDs
tryCatch(
  expr = {
    # Get time series unique identifiers
    deviceDeploymentIDs <-
      pas %>%
      pas_getDeviceDeploymentIDs()
  },
  error = function(e) {
    msg <- paste('deviceDeploymentID not found: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# ------ Create AirSensor objects ----------------------------------------------

# Init counts
successCount <- 0
count <- 0

dataList <- list()

for ( deviceDeploymentID in deviceDeploymentIDs ) {
  
  count <- count + 1
  
  # Debug info
  logger.debug(
    "%4d/%d pat_createAirSensor(id = '%s')",
    count,
    length(deviceDeploymentIDs),
    deviceDeploymentID
  )
  
  # Load the pat data, convert to an airsensor and add to dataList
  dataList[[deviceDeploymentID]] <- tryCatch(
    expr = {
      airsensor <- pat_load(
        id = deviceDeploymentID,
        label = NULL,
        pas = pas,
        startdate = startdate,
        enddate = enddate,
        timezone = "UTC"
      ) %>%
        pat_createAirSensor(
          FUN = AirSensor::PurpleAirQC_hourly_AB_01
        )
    }, 
    error = function(e) {
      logger.warn('Unable to load PAT data for %s ', deviceDeploymentID)
      NULL
    }
    
    # Keep going in the face of errors
  )
  
} # END of deviceDeploymentIDs loop

# Combine the airsensors into a single ws_monitor opbject and save
tryCatch(
  expr = {
    logger.info('Combining airsensors...')
    
    airsensor <- PWFSLSmoke::monitor_combine(dataList)
    class(airsensor) <- c("airsensor", "ws_monitor", "list")
    
    logger.info('Combined successfully...')
    
    filename <- paste0("airsensor_", opt$collectionName, "_", monthstamp, ".rda")
    filepath <- file.path(outputDir, filename)
    
    save(list = "airsensor", file = filepath)
    logger.info("Saved: %s", filename)
  }, 
  error = function(e) {
    msg <- paste("Error creating monthly AirSensor file: ", e)
    logger.fatal(msg)
  }
)

# Guarantee that the errorLog exists
if ( !file.exists(errorLog) ) dummy <- file.create(errorLog)
logger.info("Completed successfully!")

