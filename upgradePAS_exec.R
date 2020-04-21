#!/usr/local/bin/Rscript

# This Rscript will upgrade pas files created with version 0.5 of the package
# and copy them to a new location. 
#

#  ---- . AirSensor 0.7.x . ----
VERSION = "0.7.x"

# The following packages are attached here so they show up in the sessionInfo
suppressPackageStartupMessages({
  library(MazamaCoreUtils)
  library(AirSensor)
})

# ----- Get command line arguments ---------------------------------------------

if ( interactive() ) {
  
  # RStudio session
  opt <- list(
    oldBaseDir = file.path(getwd(), "output_old"),
    newBaseDir = file.path(getwd(), "output_new"),
    logDir = file.path(getwd(), "logs"),
    spatialDataDir = "~/Data/Spatial",
    version = FALSE
  )  
  
} else {
  
  # Set up OptionParser
  library(optparse)

  option_list <- list(
    make_option(
      c("-o","--oldBaseDir"), 
      default = getwd(), 
      help = "Base directory containing old pas files [default = \"%default\"]"
    ),
    make_option(
      c("-n","--newBaseDir"), 
      default = getwd(), 
      help = "Base directory containing upgraded pas files [default = \"%default\"]"
    ),
    make_option(
      c("-l","--logDir"), 
      default = getwd(), 
      help = "Output directory for generated .log file [default = \"%default\"]"
    ),
    make_option(
      c("-s","--spatialDataDir"), 
      default = "/home/mazama/data/Spatial", 
      help = "Directory containing spatial datasets used by MazamaSpatialUtils [default = \"%default\"]"
    ),
    make_option(
      c("-V","--version"), 
      action = "store_true", 
      default = FALSE, 
      help = "Print out version number [default = \"%default\"]"
    )
  )
  
  # Parse arguments
  opt <- parse_args(OptionParser(option_list = option_list))
  
}

# Print out version and quit
if ( opt$version ) {
  cat(paste0("upgradePAS_exec.R ", VERSION, "\n"))
  quit()
}

# ----- Validate parameters ----------------------------------------------------

if ( !dir.exists(opt$oldBaseDir) ) 
  stop(paste0("oldBaseDir not found:  ",opt$oldBaseDir))

if ( !dir.exists(opt$newBaseDir) ) 
  stop(paste0("newBaseDir not found:  ",opt$newBaseDir))

if ( !dir.exists(opt$logDir) ) 
  stop(paste0("logDir not found:  ",opt$logDir))

if ( !dir.exists(opt$spatialDataDir) ) 
  stop(paste0("spatialDataDir not found:  ",opt$spatialDataDir))

# ----- Set up logging ---------------------------------------------------------

logger.setup(
  traceLog = file.path(opt$logDir, "upgradePAS_TRACE.log"),
  debugLog = file.path(opt$logDir, "upgradePAS_DEBUG.log"), 
  infoLog  = file.path(opt$logDir, "upgradePAS_INFO.log"), 
  errorLog = file.path(opt$logDir, "upgradePAS_ERROR.log")
)

# For use at the very end
errorLog <- file.path(opt$logDir, "upgradePAS_ERROR.log")

if ( interactive() ) {
  logger.setLevel(TRACE)
}
  
# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running upgradePAS_exec.R version %s\n",VERSION)
optString <- paste(capture.output(str(opt)), collapse = "\n")
logger.debug("Script options: \n\n%s\n", optString)
sessionString <- paste(capture.output(sessionInfo()), collapse = "\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ------ Upgrde PAS ------------------------------------------------------------

result <- try({
  
  # Set up MazamaSpatialUtils
  AirSensor::initializeMazamaSpatialUtils(opt$spatialDataDir)

  for ( file in list.files(opt$oldBaseDir) ) {

    logger.trace("Working on %s ...", file)

    result <- try({
      old_pas <- MazamaCoreUtils::loadDataFile(file, dataDir = opt$oldBaseDir)
      pas <- pas_upgrade(old_pas)
      save(pas, file = file.path(opt$newBaseDir, file))
    }, silent = FALSE)

    if ( "try-error" %in% class(result) ) {
      logger.warn("Skipping %s ...", file)
    }

  }
  
}, silent = TRUE)

# Handle errors
if ( "try-error" %in% class(result) ) {
  msg <- paste("Error upgrading PAS files: ", geterrmessage())
  logger.fatal(msg)
} else {
  # Guarantee that the errorLog exists
  if ( !file.exists(errorLog) ) dummy <- file.create(errorLog)
  logger.info("Completed successfully!")
}

