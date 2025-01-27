# The function `message_completed` to create the green "...completed" message
# only exists to hide the option `in_builder` in dots
message_completed <- function(x, in_builder = FALSE) {
  if (isFALSE(in_builder)) {
    str <- paste0(my_time(), " | ", x)
    cli::cli_alert_success("{.field {str}}")
  } else if (in_builder) {
    cli::cli_alert_success("{my_time()} | {x}")
  }
}

user_message <- function(x, type) {
  if (type == "done") {
    cli::cli_alert_success("{my_time()} | {x}")
  } else if (type == "todo") {
    cli::cli_ul("{my_time()} | {x}")
  } else if (type == "info") {
    cli::cli_alert_info("{my_time()} | {x}")
  } else if (type == "oops") {
    cli::cli_alert_danger("{my_time()} | {x}")
  }
}

my_time <- function() strftime(Sys.time(), format = "%H:%M:%S")

# custom mode function from https://stackoverflow.com/questions/2547402/is-there-a-built-in-function-for-finding-the-mode/8189441
custom_mode <- function(x, na.rm = TRUE) {
  if(na.rm){x <- x[!is.na(x)]}
  ux <- unique(x)
  return(ux[which.max(tabulate(match(x, ux)))])
}

rule_header <- function(x) {
  rlang::inform(
    cli::rule(
      left = ifelse(is_installed("crayon"), crayon::bold(x), glue::glue("\033[1m{x}\033[22m")),
      right = paste0("nflfastR version ", utils::packageVersion("nflfastR")),
      width = getOption("width")
    )
  )
}

rule_footer <- function(x) {
  rlang::inform(
    cli::rule(
      left = ifelse(is_installed("crayon"), crayon::bold(x), glue::glue("\033[1m{x}\033[22m")),
      width = getOption("width")
    )
  )
}

# read qs files form an url
qs_from_url <- function(url) qs::qdeserialize(curl::curl_fetch_memory(url)$content)

# read rds that has been pre-fetched
read_raw_rds <- function(raw) {
  con <- gzcon(rawConnection(raw))
  ret <- readRDS(con)
  close(con)
  return(ret)
}

# helper to make sure the output of the
# schedule scraper is not named 'invalid' if the source file not yet exists
maybe_valid <- function(id) {
  all(
    length(id) == 1,
    is.character(id),
    substr(id, 1, 4) %in% seq.int(1999, as.integer(format(Sys.Date(), "%Y")) + 1, 1),
    as.integer(substr(id, 6, 7)) %in% seq_len(22),
    str_extract_all(id, "(?<=_)[:upper:]{2,3}")[[1]] %in% nflfastR::teams_colors_logos$team_abbr
  )
}

# check if a package is installed
is_installed <- function(pkg) requireNamespace(pkg, quietly = TRUE)

# load raw game files esp. for debugging
load_raw_game <- function(game_id, qs = FALSE){

  if (isTRUE(qs) && !is_installed("qs")) {
    cli::cli_abort("Package {.val qs} required for argument {.val qs = TRUE}. Please install it.")
  }

  season <- substr(game_id, 1, 4)
  path <- "https://raw.githubusercontent.com/guga31bb/nflfastR-raw/master/raw"

  if(isFALSE(qs)) fetched <- curl::curl_fetch_memory(glue::glue("{path}/{season}/{game_id}.rds"))

  if(isTRUE(qs)) fetched <- curl::curl_fetch_memory(glue::glue("{path}/{season}/{game_id}.qs"))

  if (fetched$status_code == 404 & maybe_valid(game_id)) {
    cli::cli_abort("The requested GameID {game_id} is not loaded yet, please try again later!")
  } else if (fetched$status_code == 500) {
    cli::cli_abort("The data hosting servers are down, please try again later!")
  } else if (fetched$status_code == 404) {
    cli::cli_abort("The requested GameID {game_id} is invalid!")
  }

  if(isFALSE(qs)) raw_data <- read_raw_rds(fetched$content)

  if(isTRUE(qs)) raw_data <- qs::qdeserialize(fetched$content)

  return(raw_data)

}

# Identify sessions with sequential future resolving
is_sequential <- function() inherits(future::plan(), "sequential")

check_stat_ids <- function(seasons, stat_ids){

  if (is_sequential()) {
    cli::cli_alert_info(c(
        "It is recommended to use parallel processing when using this function.",
        "Please consider running {.code future::plan(\"multisession\")}!",
        "Will go on sequentially..."
    ))
  }

  games <- nflreadr::load_schedules() %>%
    dplyr::filter(!is.na(.data$result), .data$season %in% seasons) %>%
    dplyr::pull(.data$game_id)

  p <- progressr::progressor(along = games)

  furrr::future_map_dfr(games, function(id, stats, p){
    raw_data <- load_raw_game(id)
    plays <- janitor::clean_names(raw_data$data$viewer$gameDetail$plays) %>%
      dplyr::select(.data$play_id, .data$play_stats)

    p(sprintf("ID=%s", as.character(id)))

    tidyr::unnest(plays, cols = c("play_stats")) %>%
      janitor::clean_names() %>%
      dplyr::filter(.data$stat_id %in% stats) %>%
      dplyr::mutate(game_id = as.character(id)) %>%
      dplyr::select(
        "game_id",
        "play_id",
        "stat_id",
        "yards",
        "team_abbr" = "team_abbreviation",
        "player_name",
        "gsis_player_id"
      )
  }, stat_ids, p)
}

# compute most recent season
most_recent_season <- function(roster = FALSE) {
  today <- Sys.Date()
  current_year <- as.integer(format(today, format = "%Y"))
  current_month <- as.integer(format(today, format = "%m"))

  if ((isFALSE(roster) && current_month >= 9) ||
      (isTRUE(roster) && current_month >= 3)) {
    return(current_year)
  }

  return(current_year - 1)
}

# take a time string of the format "MM:SS" and convert it to seconds
time_to_seconds <- function(time){
  as.numeric(strptime(time, format = "%M:%S")) -
    as.numeric(strptime("0", format = "%S"))
}

# write season pbp to a connected db
write_pbp <- function(seasons, dbConnection, tablename){
  p <- progressr::progressor(along = seasons)
  purrr::walk(seasons, function(x, p){
    pbp <- nflreadr::load_pbp(x)
    if (!DBI::dbExistsTable(dbConnection, tablename)){
      pbp <- dplyr::bind_rows(default_play, pbp)
    }
    DBI::dbWriteTable(dbConnection, tablename, pbp, append = TRUE)
    p("loading...")
  }, p)
}

make_nflverse_data <- function(data, type = c("play by play")){
  attr(data, "nflverse_timestamp") <- Sys.time()
  attr(data, "nflverse_type") <- type
  attr(data, "nflfastR_version") <- packageVersion("nflfastR")
  class(data) <- c("nflverse_data", "tbl_df", "tbl", "data.table", "data.frame")
  data
}
