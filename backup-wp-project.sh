#!/usr/bin/env bash

# Variables from command line
ITER=1
for arg in "$@"
do
  NUMBER=$((ITER + 1))
  VALUE=${!NUMBER}
  if [ "$arg" == "--command" ] || [ "$arg" == "-c" ]; then
    COMMAND=$VALUE # command to run
  elif [ "$arg" == "--backup_filename" ] || [ "$arg" == "-b" ]; then
    BACKUPFILENAME=$VALUE # command to run
  elif [ "$arg" == "--path" ] || [ "$arg" == "-p" ]; then
    PROJECT_PATH=$VALUE # path to main project folder on server
  elif [ "$arg" == "--quiet" ] || [ "$arg" == "-q" ]; then
    QUIET=$VALUE # options for --quite commands
  fi
  ITER=$((ITER + 1))
done

# Settings varialbles
DROPBOX_UPLOADER_DOWNLOAD_URL='https://raw.githubusercontent.com/andreafabrizi/Dropbox-Uploader/master/dropbox_uploader.sh'
DROPBOX_UPLOADER='dropbox_uploader.sh'
WP_CLI_DOWNLOAD_URL='https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar'
WP_CLI='wp'
THEME_PATH='/themes/your-theme-name/'

# Green printing
printGrn() {
  printf "\e[92m${1}\e[0m \n" || exit
}

# DropboxUploader script download function
download() {
  if [ `which curl` ]; then
    curl -s "$1" > "$2";
  elif [ `which wget` ]; then
    wget -nv -O "$2" "$1"
  fi
}

# Print header
printGrn "\n---------------------------"
printGrn "|  Dropbox Backup Script  |"
printGrn "---------------------------"

# Check is DropboxUploader available
printGrn ">> Check DropboxUploader script..."
cd "${PROJECT_PATH}${THEME_PATH}/bin" || exit
if [ ! -f "${DROPBOX_UPLOADER}" ]; then
  # Download DropboxUploader
  printGrn ">>>> Download DropboxUploader script..."
  download $DROPBOX_UPLOADER_DOWNLOAD_URL $DROPBOX_UPLOADER
  chmod +x $DROPBOX_UPLOADER
fi

# Make files backup tar.gz
makeFilesBackup() {
  cd "${PROJECT_PATH}" || exit
  # Check quiet mode
  VERBOSE_TAR='v'
  if [ -n "$QUIET" ]; then VERBOSE_TAR=''; fi
  # TarGz all files inside wp-content
  printGrn ">> Create tar.gz archive..."
  tar -cz${VERBOSE_TAR}f "${1}.tar.gz" *
}

# Check is wp command available
checkWpCLI() {
  printGrn ">> Check Wordpress CLI..."
  cd "${PROJECT_PATH}${THEME_PATH}" || exit
  if ! [ -x "$(command -v ${WP_CLI})" ]; then
    WP_CLI="${THEME_PATH}/bin/wp-cli.phar"
    if [ ! -f "$WP_CLI" ]; then
      # Download WP CLI
      printGrn ">>>> Download & install WordPress CLI..."
      download $WP_CLI_DOWNLOAD_URL $WP_CLI
      chmod +x $WP_CLI
      WP_CLI="php ${WP_CLI}"
    else
      printGrn ">>>> Self update WordPress CLI..."
      $WP_CLI cli update --yes $QUIET
    fi
  fi
}

# Make db backup tar.gz
makeDbBackup() {
  checkWpCLI
  cd "${PROJECT_PATH}" || exit
  printGrn ">> Export wp database..."
  ${WP_CLI} db export "${1}.sql"
  printGrn ">> Create tar.gz archive..."
  # Check quiet mode
  VERBOSE_TAR='v'
  if [ -n "$QUIET" ]; then VERBOSE_TAR=''; fi
  # TarGz exported db sql file
  tar -cz${VERBOSE_TAR}f "${1}.tar.gz" "${1}.sql"
  rm "${1}.sql"
}

# List backup files

# Restore files backup
# $1 - backup filename
restoreFileBackup() {
  cd "${PROJECT_PATH}" || exit
  printGrn ">> Remove all files..."
  $ find . -type f ! -name "${1}" -exec rm -rf {} \;
  printGrn ">> Unpack tar.gz archive..."
  # Check quiet mode
  VERBOSE_TAR='v'
  if [ -n "$QUIET" ]; then VERBOSE_TAR=''; fi
  tar -xz${VERBOSE_TAR}f "${1}"
  printGrn ">> Remove backup tar files..."
  rm "${1}"
}

# Restore db backup
restoreDbBackup() {
  cd "${PROJECT_PATH}" || exit
  printGrn ">> Unpack tar.gz archive..."
  # Check quiet mode
  VERBOSE_TAR='v'
  if [ -n "$QUIET" ]; then VERBOSE_TAR=''; fi
  tar -xz${VERBOSE_TAR}f "${1}"
  printGrn ">> Importing database by wpcli..."
  FILENAME="$(basename -- ${1})"
  FILENAME="${FILENAME%%.*}"
  ${WP_CLI} db import "${FILENAME}.sql" --quiet
  printGrn ">> Remove backup tar & sql files..."
  cd "${PROJECT_PATH}" || exit
  rm "${FILENAME}.tar.gz" "${FILENAME}.sql"
}

# Download backup file
downloadBackupFile() {
  cd "${PROJECT_PATH}" || exit
  printGrn ">> Download backup file..."
  # Check quiet mode
  if [ -n "$QUIET" ]; then QUIET_UPLOAD='-q'; fi
  ${PROJECT_PATH}${THEME_PATH}/bin/./${DROPBOX_UPLOADER} download "${1}" ${QUIET_UPLOAD}
}

# Upload backup file
uploadBackupFile() {
  cd "${PROJECT_PATH}" || exit
  printGrn ">> Upload backup file..."
  # Check quiet mode
  if [ -n "$QUIET" ]; then QUIET_UPLOAD='-q'; fi
  ${PROJECT_PATH}${THEME_PATH}/bin/./${DROPBOX_UPLOADER} upload "${1}" "${1}" ${QUIET_UPLOAD}
  rm "${1}"
}

# Commands

## Backup only files
if [ "${COMMAND}" == "files" ]; then
  DATE=$(date +'%d-%m-%Y_%H-%M')
  makeFilesBackup "files_${DATE}"
  uploadBackupFile "files_${DATE}.tar.gz"
fi

## Backup only db
if [ "${COMMAND}" == "database" ]; then
  DATE=$(date +'%d-%m-%Y_%H-%M')
  makeDbBackup "database_${DATE}"
  uploadBackupFile "database_${DATE}.tar.gz"
fi

## Backup db and files
if [ "${COMMAND}" == "full" ]; then
  DATE=$(date +'%d-%m-%Y_%H-%M')
  makeDbBackup "database_${DATE}"
  makeFilesBackup "full_${DATE}"
  uploadBackupFile "full_${DATE}.tar.gz"
fi

## Show backup list
if [ "${COMMAND}" == "list" ]; then
  cd "${PROJECT_PATH}/${THEME_PATH}/bin" || exit
  ${THEME_PATH}/bin/./${DROPBOX_UPLOADER} list
fi

## Restore backup
if [ "${COMMAND}" == "restore" ]; then
  cd "${PROJECT_PATH}" || exit
  downloadBackupFile "${BACKUPFILENAME}"
  
  # Restore files backup
  if [[ ${BACKUPFILENAME} == "files_"* ]]; then
    restoreFileBackup "${BACKUPFILENAME}"
  fi
  
  # Restore database backup
  if [[ ${BACKUPFILENAME} == "database_"* ]]; then
    restoreDbBackup "${BACKUPFILENAME}"
  fi
  
  # Restore files and db backup
  if [[ ${BACKUPFILENAME} == "full_"* ]]; then
    restoreFileBackup "${BACKUPFILENAME}"
    restoreDbBackup "${BACKUPFILENAME}"
  fi
fi

# Print footer
printGrn "-------------------------------"
printGrn "|  Dropbox Backup Script End  |"
printGrn "-------------------------------\n"

