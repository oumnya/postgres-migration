#!/bin/bash

set -o pipefail

export TERM=ansi
_GREEN=$(tput setaf 2)
_BLUE=$(tput setaf 4)
_MAGENTA=$(tput setaf 5)
_CYAN=$(tput setaf 6)
_RED=$(tput setaf 1)
_YELLOW=$(tput setaf 3)
_RESET=$(tput sgr0)
_BOLD=$(tput bold)

# Function to print error messages and exit
error_exit() {
    printf "[ ${_RED}ERROR${_RESET} ] ${_RED}$1${_RESET}\n" >&2
    exit 1
}

section() {
  printf "${_RESET}\n"
  echo "${_BOLD}${_BLUE}==== $1 ====${_RESET}"
}

write_ok() {
  echo "[$_GREEN OK $_RESET] $1"
}

write_warn() {
  echo "[$_YELLOW WARN $_RESET] $1"
}

trap 'echo "An error occurred. Exiting..."; exit 1;' ERR

printf "${_BOLD}${_MAGENTA}"
echo "+-------------------------------------+"
echo "|                                     |"
echo "|  Railway Postgres Migration Script  |"
echo "|                                     |"
echo "+-------------------------------------+"
printf "${_RESET}\n"

echo "For more information, see https://docs.railway.app/database/migration"
echo "If you run into any issues, please reach out to us on Discord: https://discord.gg/railway"
printf "${_RESET}\n"

section "Validating environment variables"

# Validate that PLUGIN_DATABASE_URL environment variable exists
if [ -z "$PLUGIN_DATABASE_URL" ]; then
    error_exit "PLUGIN_DATABASE_URL environment variable is not set."
fi

# Validate that PLUGIN_DATABASE_URL contains the string "containers"
if [[ "$PLUGIN_DATABASE_URL" != *"containers-us-west"* ]]; then
    error_exit "PLUGIN_DATABASE_URL is not a Railway plugin database URL."
fi

write_ok "PLUGIN_DATABASE_URL correctly set"

# Validate that NEW_DATABASE_URL environment variable exists
if [ -z "$NEW_DATABASE_URL" ]; then
    error_exit "NEW_DATABASE_URL environment variable is not set."
fi

write_ok "NEW_DATABASE_URL correctly set"

section "Checking if NEW_DATABASE_URL is empty"

# Query to check if there are any tables in the new database
query="SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('information_schema', 'pg_catalog');"
table_count=$(psql "$NEW_DATABASE_URL" -t -A -c "$query")

if [[ $table_count -eq 0 ]]; then
  if [ -z "$OVERWRITE_DATABASE" ]; then
    echo "The new database is empty. Proceeding with restore."
  fi
else
  if [ -z "$OVERWRITE_DATABASE" ]; then
    error_exit "The new database is not empty. Aborting migration.\nSet the OVERWRITE_DATABASE environment variable to overwrite the new database."
  fi
  write_warn "The new database is not empty. Found OVERWRITE_DATABASE environment variable. Proceeding with restore."
fi

section "Dumping database from PLUGIN_DATABASE_URL" 

# Run pg_dump on the plugin database
dump_file="plugin_dump.sql"
pg_dump -Fc "$PLUGIN_DATABASE_URL" > "$dump_file" || error_exit "Failed to dump database from $PLUGIN_DATABASE_URL."

write_ok "Successfully saved dump to $dump_file"

dump_file_size=$(ls -lh "$dump_file" | awk '{print $5}')
echo "Dump file size: $dump_file_size"

section "Restoring database to NEW_DATABASE_URL"

# Restore that data to the new database
pg_restore -d "$NEW_DATABASE_URL" "$dump_file" || error_exit "Failed to restore database to $NEW_DATABASE_URL."

write_ok "Successfully restored database to NEW_DATABASE_URL"

printf "${_RESET}\n"
printf "${_RESET}\n"
echo "${_BOLD}${_GREEN}Database completed successfully${_RESET}"
printf "${_RESET}\n"
echo "Next steps..."
echo "1. Update your application's DATABASE_URL environment variable to point to the new database."
echo '  - You can use variable references to do this. For example `${{ Postgres.DATABASE_URL }}`'
echo "2. Verify that your application is working as expected."
echo "3. Remove the legacy plugin and this service from your Railway project."

printf "${_RESET}\n"
