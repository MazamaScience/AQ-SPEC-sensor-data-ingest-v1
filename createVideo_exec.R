#!/usr/local/bin/Rscript

# This Rscript generates a video for a South Coast community over a 7-day 
# period. If an endDate is given, then that day and the previous 6 are covered.
# If no endDate is given then the last 7 days are covered. Resulting video
# is labeled by the communitiy's South Coast ID.
#
# Test this script from the command line with:
#
# ./createVideo_exec.R --communityID="SCSB" -s 20190704 -r 4 -o ~/Desktop/ -v TRUE 
# ./createVideo_exec.R -c SCSB -o test/data

# ----- . AirSensor 1.1.x . first pass
VERSION = "0.4.0"

# The following packages are attached here so they show up in the sessionInfo
suppressPackageStartupMessages({
  library(MazamaCoreUtils)
  library(MazamaSpatialUtils)
  library(AirSensor)
  
  # setArchiveBaseUrl("http://smoke.mazamascience.com/data/PurpleAir")
})

# Load all shared utility functions
utilFiles <- list.files("R", pattern = ".+\\.R", full.names = TRUE)

for (file in utilFiles) {
  source(file.path(getwd(), file))
}

# ----- Get command line arguments ---------------------------------------------

if ( interactive() ) {
  
  # RStudio session
  opt <- list(
    archiveBaseDir = file.path(getwd(), "data"),
    logDir = file.path(getwd(), "logs"),
    communityID = "SCUV",
    datestamp = NULL,
    timezone = "America/Los_Angeles",
    days = 7,
    frameRate = 6,
    version = FALSE
  )  
  
} else {
  
  # Set up OptionParser
  library(optparse)
  
  option_list <- list(
    make_option(
      c("-o","--archiveBaseDir"), 
      default = getwd(), 
      help = "Output directory for generated video file [default=\"%default\"]"
    ),
    make_option(
      c("-c","--communityID"), 
      default = "", 
      help = "ID of the South Coast community [default=\"%default\"]"
    ),
    make_option(
      c("-d","--datestamp"), 
      default = NULL, 
      help = "Datestamp specifying the date [default=today]"
    ),
    make_option(
      c("-t","--timezone"), 
      default = "America/Los_Angeles", 
      help = "Timezone used to interpret datestamp  [default=\"%default\"]"
    ),
    make_option(
      c("-y","--days"), 
      default = 7, 
      help = "Days covered by the video  [default=\"%default\"]"
    ),
    make_option(
      c("-r","--frameRate"), 
      default = 6, 
      help = "Frames per second [default=\"%default\"]"
    ),
    make_option(
      c("-v","--verbose"), 
      default = FALSE, 
      help = "Print out generated frame files [default=\"%default\"]"
    ),
    make_option(
      c("-l","--logDir"), 
      default = getwd(), 
      help = "Output directory for generated .log file [default=\"%default\"]"
    ),
    make_option(
      c("-V","--version"), 
      action = "store_true", 
      default = FALSE, 
      help = "Print out version number [default=\"%default\"]"
    )
  )
  
  # Parse arguments
  opt <- parse_args(OptionParser(option_list = option_list))
}

# Print out version and quit
if (opt$version) {
  cat(paste0("createVideo_exec.R ", VERSION, "\n"))
  quit()
}

# ----- Validate parameters ----------------------------------------------------

if (opt$frameRate < 0 || opt$frameRate != floor(opt$frameRate)) {
  stop("frameRate must be a positive integer")
}

if (opt$communityID == "") {
  stop("Must define a community ID")
}

if ( dir.exists(opt$archiveBaseDir) ) {
  setArchiveBaseDir(opt$archiveBaseDir)
} else {
  stop(paste0("archiveBaseDir not found:  ",opt$archiveBaseDir))
}

if ( !dir.exists(opt$logDir) ) 
  stop(paste0("logDir not found:  ",opt$logDir))

# ----- Set up logging ---------------------------------------------------------

logger.setup(
  traceLog = file.path(opt$logDir, "createVideo_TRACE.log"),
  debugLog = file.path(opt$logDir, "createVideo_DEBUG.log"), 
  infoLog  = file.path(opt$logDir, "createVideo_INFO.log"), 
  errorLog = file.path(opt$logDir, "createVideo_ERROR.log")
)

# For use at the very end
errorLog <- file.path(opt$logDir, "createVideo_ERROR.log")

# Silence other warning messages
options(warn = -1) # -1=ignore, 0=save/print, 1=print, 2=error

# Start logging
logger.info("Running createVideo_exec.R version %s", VERSION)
optionsString <- paste(capture.output(str(opt)), collapse = '\n')
logger.debug('Command line options:\n\n%s\n', optionsString)
sessionString <- paste(capture.output(sessionInfo()), collapse = "\n")
logger.debug("R session:\n\n%s\n", sessionString)

# ----- Set up community regions -----------------------------------------------

communityRegionList <- list(
  SCAP = "Alhambra/Monterey Park",
  SCBB = "Big Bear Lake",
  SCEM = "El Monte",
  SCIV = "Imperial Valley",
  SCNP = "Nipomo",
  SCPR = "Paso Robles",
  SCSJ = "San Jacinto",
  SCSB = "Seal Beach",
  SCAH = "SCAH", # Oakland
  SCAN = "SCAN",
  SCUV = "SCUV", # West LA
  SCSG = "South Gate",
  SCHS = "Sycamore Canyon",
  SCTV = "Temescal Valley"
)

communityGeoMapInfo <- list(
  SCAP = list(lon = -118.132324, lat = 34.072205, zoom = 13),
  SCBB = list(lon = -116.898568, lat = 34.255736, zoom = 13),
  SCEM = list(lon = -118.034595, lat = 34.069292, zoom = 12),
  SCIV = list(lon = -115.551228, lat = 32.980878, zoom = 14),
  SCNP = list(lon = -120.555047, lat = 35.061590, zoom = 12),
  SCPR = list(lon = -120.67, lat = 35.57, zoom = 11),
  SCSJ = list(lon = -116.958228, lat = 33.765083, zoom = 14),
  SCSB = list(lon = -118.083084, lat = 33.767033, zoom = 15),
  SCAH = list(lon = -122.14, lat = 37.66, zoom = 11),
  SCAN = list(lon = -122.307492, lat = 37.964949, zoom = 12),
  SCUV = list(lon = -118.427781, lat = 34.023917, zoom = 15),
  SCSG = list(lon = -118.178104, lat = 33.934260, zoom = 13),
  SCHS = list(lon = -117.307598, lat = 33.947524, zoom = 15),
  SCTV = list(lon = -117.481278, lat = 33.753517, zoom = 12)
)

# ----- Create videos ----------------------------------------------------------

# Timezone is passed in local time

result <- try({

  # Get date range 
  # NOTE:  We use 'ceilingEnd' here because sensorLoad() trims to day boundaries
  # NOTE:  and ends just before 'enddate'.
  dateRange <- MazamaCoreUtils::dateRange(
    enddate = opt$datestamp,
    timezone = opt$timezone,
    unit = "day",
    ceilingEnd = TRUE,
    days = opt$days
  )
  
  # NOTE:  Force default (datestamp == NULL) to end at yesterday midnight instead
  # NOTE:  of tonight. 
  
  if ( is.null(opt$datestamp) ) {
    dateRange <- dateRange - lubridate::ddays(1)
  }
  
  # Get the year in local time
  yearStamp <- strftime(dateRange[2], "%Y", tz = opt$timezone)
  monthStamp <- strftime(dateRange[2], "%m", tz = opt$timezone)
  
  # Create directory if it doesn't exist
  outputDir <- file.path(opt$archiveBaseDir, "videos", yearStamp, monthStamp)
  logger.info("Output directory: %s", outputDir)
  
  if ( !dir.exists(outputDir) ) {
    dir.create(outputDir, recursive = TRUE)
  }
    
  # Load sensor data
  logger.info("Loading sensor data")
  sensor <- sensor_load(
    collection = "scaqmd",
    startdate = dateRange[1], 
    enddate = dateRange[2]
  )
  
  # Retrieve both the community name and ID. Prioritize name over ID if they are
  # different.
  if ( opt$communityID != "" ) {
    
    opt$communityID <- toupper(opt$communityID)
    communityRegion <- communityRegionList[[opt$communityID]]
    communityMeta <- dplyr::filter(sensor$meta, communityRegion == !!communityRegion)
    if (nrow(communityMeta) == 0) {
      stop(paste0("Community with ID '", opt$communityID, "' has no monitors"))
    }

  } else {
    
    stop("Must provide a South Coast community name or ID")
    
  }
  
  mapInfo <- communityGeoMapInfo[[opt$communityID]]
  
  # Time axis data
  logger.info("Preparing the time axis")
  if ( opt$days <= 3 ) {
    tickSkip <- 6
  } else if ( opt$days <= 6 ) {
    tickSkip <- 12
  } else {
    tickSkip <- 24
  }
  
  # Option to manipulate the data here
  movieData <- sensor
  
  tAxis <- movieData$data$datetime
  tAxis[(lubridate::hour(tAxis) - 1) %% tickSkip == 0 & 
           lubridate::minute(tAxis) == 0]
  tTicks <- tAxis[(lubridate::hour(tAxis) - 1) %% tickSkip == 0 & 
                     lubridate::minute(tAxis) == 0]
  tLabels <- strftime(tTicks, "%l %P", tz = opt$timezone)
  tInfo <- PWFSLSmoke::timeInfo(tAxis, longitude = mapInfo$lon, latitude = mapInfo$lat)
  
  # Load a static map image of the community
  logger.info("Loading static map of community '%s'", communityRegion)
  
  staticMap <- 
    PWFSLSmoke::staticmap_getStamenmapBrick(
      centerLon = mapInfo$lon,
      centerLat = mapInfo$lat,
      zoom = mapInfo$zoom,
      width = 770,
      height = 495
    )
  
  # Generate individual frames
  logger.info("Generating %s video frames", length(tAxis))
  for (i in 1:length(tAxis)) {
    frameTime <- tAxis[i]
    number <- stringr::str_pad(i, 3, 'left', '0')
    fileName <- paste0(opt$communityID, number, ".png")
    filePath <- file.path(tempdir(), fileName)
    ###png(filePath, width = 1280, height = 720, units = "px")
    par(cex = 0.75)
    png(filePath, width = 960, height = 540, units = "px")
    logger.trace("Generating frame %s: %s", 
                 number, 
                 strftime(frameTime, "%b %d %H:%M", tz = opt$timezone))
    sensor_videoFrame(
      sensor,
      communityRegion = communityRegion,
      frameTime = frameTime,
      timeInfo = tInfo,
      timeAxis = tAxis,
      timeTicks = tTicks,
      timeLabels = tLabels,
      map = staticMap
    )
    if (opt$verbose) {
      print(strftime(frameTime, "%b %d %H:%M", tz = opt$timezone))
    }
    par(cex = 1)
    dev.off()
  }
  
  # Create a file name timestamped with the final frameTime in the
  # "America/Los_Angeles" timezone
  fileName <- paste0(
    opt$communityID, "_",
    strftime(dateRange[2], "%Y%m%d", tz = opt$timezone),
    ".mp4"
  )

  # Define system calls to ffmpeg to create video from frames
  cmd_cd <- paste0("cd ", tempdir())
  cmd_ffmpeg <- paste0(
    "ffmpeg -y -loglevel quiet -r ", 
    ###opt$frameRate, " -f image2 -s 1280x720 -i ", 
    opt$frameRate, " -f image2 -s 960x540 -i ", 
    opt$communityID, "%03d.png -vcodec libx264 -crf 25 ", 
    # https://bugzilla.mozilla.org/show_bug.cgi?id=1368063#c7
    "-pix_fmt yuv420p ",
    outputDir, "/", fileName
  )
  cmd_rm <- paste0("rm *.png")
  cmd <- paste0(cmd_cd, " && ", cmd_ffmpeg, " && ", cmd_rm)
  
  # Make system calls
  logger.info("Calling ffmpeg to make video from frames")
  logger.trace(cmd)

  ffmpegString <- paste(capture.output(system(cmd)), collapse = "\n")

  logger.trace("ffmpeg output:\n\n%s\n", ffmpegString)
  
}, silent = TRUE)

if (opt$verbose) {
  print(result)
}

# Handle errors
if ( "try-error" %in% class(result) ) {
  msg <- paste("Error creating video: ", geterrmessage())
  logger.fatal(msg)
} else {
  # Guarantee that the errorLog exists
  if ( !file.exists(errorLog) ) dummy <- file.create(errorLog)
  logger.info("Completed successfully!")
}
