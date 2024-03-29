# Sensor Data Ingest

**_Updated 2020-06-16_**

Scripts in this repository do all the work of converting raw data from Purple
Air sensors into .rda files ready for use with the **AirSensor** R package.

Data can be accesed in R with:

```
library(AirSensor)
setArchiveBaseUrl("http://data.mazamascience.com/PurpleAir/v1")
```

## Installation Instructions for an Operational Site

### Docker containers

_For background on Docker, see:_

- https://en.wikipedia.org/wiki/Docker_(software)
- https://www.docker.com

All data processing is performed by scripts running inside of docker
containers. This level of virtualization allows containers and scripts to be
loaded onto a system that has none of the other software dependencies required
to run R.

This repository includes a `docker/Makefile` with targets and
dependencies to simplify building a docker image.

You can review current `airsensor` docker images with:

```
docker images | grep "mazamascience/airsensor"
```

### Web accessible directories

It is assumed that scripts are being run on a Unix system with an Apache
web server. A data directory should be set up as the `archiveBaseDir` so that
Apache can serve GET requests for data files.

An example base directory might be:

/var/www/data.mazamascience.com/html/PurpleAir/v1

### Cron jobs

Each of the `~_exec.R` scripts is run on a daily schedule defined by
`crontab_etc/crontab_daily.txt`.

_Note that all crontab entries must be on a single line. No line continuation
characters are allowed._

The `crontab` files, along with `test/Makefile` use the docker `-v` flag to
mount host directories (aka "volumes") to predefined locations inside the
docker container.

To deploy the data ingest scripts, the contents of the `crontab` files should be
modified to reflect appropriate absolute paths on the host machine and then
added to a privileged user's crontab so the scripts will be run on a daily basis.

## Details

### Files

This directory has the following contents:

```
├── Makefile
├── README.md
├── createAirSensor_annual_exec.R
├── createAirSensor_extended_exec.R
├── createAirSensor_latest_exec.R
├── createPAS_exec.R
├── createPAT_extended_exec.R
├── createPAT_latest_exec.R
├── createPAT_monthly_exec.R
├── createVideo_exec.R
├── crontabs_etc
│   ├── __crontab_daily.txt
│   ├── crontab_PAT_monthlyArchive_joule.txt
│   ├── crontab_daily_joule.txt
│   └── upgrade_joule.txt
├── docker
│   └── Makefile
├── test
│   └── Makefile
└── upgradePAS_exec.R
```

Each of the `~_exec.R` scripts is run on a daily schedule defined by
`crontab_daily.txt` files.

The `docker/` directory has a Makefile for installing the docker image needed to
run the scripts.

The `test/` directory has a Makefile for testing every script using the
installed docker image.

### Output Directories

As each script is run, either at the command line or from a cron job, it will
generate output files in the directory specified with the `--archiveBaseDir` option.
The following directory structure is required. R package functions assume the
following directory structure will be available at some web accessible
`archiveBaseDir` or `archiveBasUrl`:

```
├── airsensor
│   ├── 2017
│   ├── 2018
│   ├── 2019
│   ├── 2020
│   └── latest
├── pas
│   ├── 2019
│   └── 2020
└── pat
    ├── 2017
    ├── 2018
    ├── 2019
    ├── 2020
    └── latest
```

Files generated by the `latest` scripts are always written into `latest/`
directories while other scripts write datestamped files into the appropriate
annual directory.

### Processing Logs

As each script is run, either at the command line or from a cron job, it will
generate logging output in the directory specified with the `--logDir` option.
Log files contain the name of the processing script. Four different levels
of logging are provided:

- `ERROR` -- Something went wrong, sometimes resulting in no generation of an output file.
- `INFO` -- Summary information on data processed along with any warnings generated.
- `DEBUG` -- Detailed processing information to help understand where processing might have gone wrong.
- `TRACE` -- _Excruciatingly_ detailed processing information including URL requests.

Note that scripts run repeatedly in cron jobs will overwrite the logs so that
any failures seen in the log files represent the most recent run of the script
generating the failure.

### Testing

The `test/` directory contains a `Makefile` with targets that will run
executable scripts using the `mazamascience/airsensor:latest` docker image. All
output and log files will be generated in `output/` and `logs/` directories
that can be removed with the `clean` target.

For example, to test the proper generation of `pas` files, one should:

```
cd test; make createPAS
```

Then review the files generated in `output/` and `logs/`.

More detailed debugging can be performed by loading the `~_exec.R` scripts into
RStudio and running them interactively.

### Background Reading

A quick refresher on docker commands is available at the
[docker cheat sheet](https://github.com/wsargent/docker-cheat-sheet).
