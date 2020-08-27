#!/usr/local/bin/Rscript

# This Rscript will ingest pat_<id>_latest7.rda files and use them to create pat
# files with extended time ranges: 45-day and monthly.
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
  # NOTE: Remeber to set the working directory for logging with setwd()
  opt <- list(
    archiveBaseDir = file.path(getwd(), "test/output"),
    logDir = file.path(getwd(), "test/logs"),
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
      help = "String patter passed to stringr::str_detect  [default = \"%default\"]"
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
  cat(paste0("createPAT_extended_exec.R ",VERSION,"\n"))
  quit()
}

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
  traceLog = file.path(opt$logDir, paste0("createPAT_extended_",regionID,"_TRACE.log")),
  debugLog = file.path(opt$logDir, paste0("createPAT_extended_",regionID,"_DEBUG.log")),
  infoLog  = file.path(opt$logDir, paste0("createPAT_extended_",regionID,"_INFO.log")),
  errorLog = file.path(opt$logDir, paste0("createPAT_extended_",regionID,"_ERROR.log"))
)

# For use at the very end
errorLog <- file.path(opt$logDir, paste0("createPAT_extended_",regionID,"_ERROR.log"))

if ( interactive() ) {
  logger.setLevel(TRACE)
}

# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createPAT_extended_exec.R version %s",VERSION)
optString <- paste(capture.output(str(opt)), collapse = "\n")
logger.debug("Script options: \n\n%s\n", optString)
sessionString <- paste(capture.output(sessionInfo()), collapse = "\n")
logger.debug("R session:\n\n%s\n", sessionString)


# ------ Get timestamps --------------------------------------------------------

tryCatch(
  expr = {
    # All datestamps are UTC
    timezone <- "UTC"

    # NOTE:  Always extend month boundaries by one UTC day on each end to make 
    # NOTE:  sure we have complete days in any local time.
    
    # Get dates and date stamps
    now <- lubridate::now(tzone = timezone)
    now_m45 <- now - lubridate::ddays(45)
    cur_monthStart <- lubridate::floor_date(now, "month") - lubridate::ddays(1)
    cur_monthEnd <- lubridate::ceiling_date(now, "month") + lubridate::ddays(1)
    cur_monthStamp <- strftime(now, "%Y%m", tz = timezone)
    cur_mmStamp <- stringr::str_sub(cur_monthStamp, 5, 6)
    prev_midMonth <- cur_monthStart - lubridate::ddays(14)
    prev_monthStart <- lubridate::floor_date(prev_midMonth, "month") - lubridate::ddays(1)
    prev_monthEnd <- lubridate::ceiling_date(prev_midMonth, "month") + lubridate::ddays(1)
    prev_monthStamp <- strftime(prev_midMonth, "%Y%m", tz = timezone)
    prev_mmStamp <- stringr::str_sub(prev_monthStamp, 5, 6)
    cur_yearStamp <- strftime(now, "%Y", tz = timezone)
    prev_yearStamp <- strftime(prev_midMonth, "%Y", tz = timezone)

  },
  error = function(e) {
    msg <- paste('Failed to create timestamps: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# Set up data directories
tryCatch(
  expr = {
    logger.trace("Setting up data directories")
    latestDataDir <- paste0(opt$archiveBaseDir, "/pat/latest")
    cur_monthlyDir <- paste0(opt$archiveBaseDir, "/pat/", cur_yearStamp, '/', cur_mmStamp)
    prev_monthlyDir <- paste0(opt$archiveBaseDir, "/pat/", prev_yearStamp, '/', prev_mmStamp)

    logger.trace("latestDataDir = %s", latestDataDir)
    logger.trace("cur_monthlyDir = %s", cur_monthlyDir)
    logger.trace("prev_monthlyDir = %s", prev_monthlyDir)

    if ( !dir.exists(cur_monthlyDir) )
      dir.create(cur_monthlyDir, showWarnings = FALSE, recursive = TRUE)

    if ( !dir.exists(prev_monthlyDir) )
      dir.create(prev_monthlyDir, showWarnings = FALSE, recursive = TRUE)
  },
  error = function(e) {
    msg <- paste('Failed to set up data directories: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# ------ Load PAS object -------------------------------------------------------

tryCatch(
  expr = {
    # SCAQMD Database
    logger.info('Loading PAS data ...')
    pas <- 
      pas_load() %>%
      pas_filter(.data$countryCode == opt$countryCode)
  },
  error = function(e) {
    msg <- paste('Fatal PAS load Execution: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# Get Unique IDs
tryCatch(
  expr = {
    logger.info('Capturing Unique Device Deployment IDs')
    deviceDeploymentIDs <- 
      pas %>%
      pas_filter(.data$DEVICE_LOCATIONTYPE == 'outside') %>%
      pas_filter(is.na(.data$parentID)) %>%
      pas_filter(stringr::str_detect(.data$label, opt$pattern)) %>%
      dplyr::pull(.data$deviceDeploymentID)
  },
  error = function(e) {
    msg <- paste('Error in Device Deployment IDs: ', e)
    logger.fatal(msg)
    stop(msg)
  }
)

# ------ Create 45-day PAT objects ---------------------------------------------

tryCatch(
  expr = {
    # init counts
    count <- 0
    successCount <- 0

    for( deviceDeploymentID in deviceDeploymentIDs ) {

      # update count
      count <- count + 1

      tryCatch(
        expr = {
          # Contruct file paths
          tryCatch(
            expr = {
              latest7Path <- file.path(latestDataDir, paste0("pat_", deviceDeploymentID, "_latest7.rda"))
              latest45Path <- file.path(latestDataDir, paste0("pat_", deviceDeploymentID, "_latest45.rda"))
              cur_monthPath <- file.path(cur_monthlyDir, paste0("pat_", deviceDeploymentID, "_", cur_monthStamp, ".rda"))
              prev_monthPath <- file.path(prev_monthlyDir, paste0("pat_", deviceDeploymentID, "_", prev_monthStamp, ".rda"))
            },
            error = function(e) {
              msg <- paste('Failed to construct file path: ', e)
              logger.fatal(msg)
              stop(msg)
            }
          )

          # Load latest7 from path
          if ( file.exists(latest7Path) ) {
            latest7 <- get(load(latest7Path))
          } else {
            logger.trace("Skipping %s, missing %s", deviceDeploymentID, latest7Path)
            next
          }

          logger.trace(
            "%4d/%d Updating %s",
            count,
            length(deviceDeploymentIDs),
            latest45Path
          )
          
          # Load latest45 from path
          if ( !file.exists(latest45Path) ) {
            
            pat_full <- latest7 # default when starting from scratch
            
          } else {
            
            latest45 <- get(load(latest45Path))
            
            # NOTE:  PWFSL monitors may come and go so the pwfsl_closest~ data might
            # NOTE:  be different in latest7 and latest45. We update the latest45
            # NOTE:  record to always use the latest7$pwfsl_closest~ data so that
            # NOTE:  pat_join() doesn't fail with:
            # NOTE:    "`pat` objects must be of the same monitor"
            latest45$meta$pwfsl_closestMonitorID <- latest7$meta$pwfsl_closestMonitorID
            latest45$meta$pwfsl_closestDistance <- latest7$meta$pwfsl_closestDistance
            
            # Join
            pat_full <- AirSensor::pat_join(latest45, latest7)
            
          }

          # Update the latest45 file (trimmed to day boundaries)
          pat <-
            pat_full %>%
            pat_filterDate(now_m45, now, timezone = latest7$meta$timezone[1])

          save(list = "pat", file = latest45Path)

          # Update the current month file
          pat <-
            pat_full %>%
            pat_filterDate(cur_monthStart, cur_monthEnd, timezone = timezone)

          save(list = "pat", file = cur_monthPath)

          # Update the previous month file until 7-days into the current month
          if ( lubridate::day(now) < 7 ) {
            pat <-
              pat_full %>%
              pat_filterDate(prev_monthStart, prev_monthEnd, timezone = timezone)

            save(list = "pat", file = prev_monthPath)
          }

          successCount <- successCount + 1
        },
        error = function(e) {
          logger.warn(e)
        }
      )

    }

  },
  error = function(e) {
    msg <- paste("Error creating extended PAT files: ", e)
    logger.fatal(msg)
  },
  finally = {
    if ( successCount == 0 ) {
      logger.fatal("0 extended PAT files were generated.")
    } else {
      logger.info("%d extended PAT files were generated.", successCount)
      logger.info("Completed successfully!")
      # Guarantee that the errorLog exists
      if ( !file.exists(errorLog) )
        dummy <- file.create(errorLog)
    }
    ptm <- proc.time()
    logger.info("User: %.0f, System: %.0f, Elapsed: %.0f seconds", ptm[1], ptm[2], ptm[3])
  }
)
