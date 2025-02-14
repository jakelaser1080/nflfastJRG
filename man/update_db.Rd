% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/helper_database_functions.R
\name{update_db}
\alias{update_db}
\title{Update or Create a nflfastR Play-by-Play Database}
\usage{
update_db(
  dbdir = getOption("nflfastR.dbdirectory", default = "."),
  dbname = "pbp_db",
  tblname = "nflfastR_pbp",
  force_rebuild = FALSE,
  db_connection = NULL
)
}
\arguments{
\item{dbdir}{Directory in which the database is or shall be located. Can also
be set globally with \code{options(nflfastR.dbdirectory)}}

\item{dbname}{File name of an existing or desired SQLite database within \code{dbdir}}

\item{tblname}{The name of the play by play data table within the database}

\item{force_rebuild}{Hybrid parameter (logical or numeric) to rebuild parts
of or the complete play by play data table within the database (please see details for further information)}

\item{db_connection}{A \code{DBIConnection} object, as returned by
\code{\link[DBI:dbConnect]{DBI::dbConnect()}} (please see details for further information)}
}
\description{
\code{update_db} updates or creates a database with \code{nflfastR}
play by play data of all completed games since 1999.
}
\details{
This function creates and updates a data table with the name \code{tblname}
within a SQLite database (other drivers via \code{db_connection}) located in
\code{dbdir} and named \code{dbname}.
The data table combines all play by play data for every available game back
to the 1999 season and adds the most recent completed games as soon as they
are available for \code{nflfastR}.

The argument \code{force_rebuild} is of hybrid type. It can rebuild the play
by play data table either for the whole nflfastR era (with \code{force_rebuild = TRUE})
or just for specified seasons (e.g. \code{force_rebuild = c(2019, 2020)}).
Please note the following behavior:
\itemize{
\item{\code{force_rebuild = TRUE}}{: The data table with the name \code{tblname}
will be removed completely and rebuilt from scratch. This is helpful when
new columns are added during the Off-Season.}
\item{\code{force_rebuild = c(2019, 2020)}}{: The data table with the name \code{tblname}
will be preserved and only rows from the 2019 and 2020 seasons will be
deleted and re-added. This is intended to be used for ongoing seasons because
the NFL fixes bugs in the underlying data during the week and we recommend
rebuilding the current season every Thursday during the season.}
}

The parameter \code{db_connection} is intended for advanced users who want
to use other DBI drivers, such as MariaDB, Postgres or odbc. Please note that
the arguments \code{dbdir} and \code{dbname} are dropped in case a \code{db_connection}
is provided but the argument \code{tblname} will still be used to write the
data table into the database.
}
