#!/usr/bin/env bash

export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

PROJECT_DIR="/home/ubuntu/demo1"
LIQUIBASE_BIN_DIR="liquibase/bin"
LIQUIBASE_URL="https://github.com/liquibase/liquibase/releases/download/liquibase-parent-3.5.3/liquibase-3.5.3-bin.tar.gz"
POSTGRES_JDBC_DRIVER_URL="https://jdbc.postgresql.org/download/postgresql-42.1.4.jar"

BUCKET_NAME="ansible-demo1"
LIQUIBASE_FILENAME="liquibase-3.5.3-bin.tar.gz"
POSTGRES_JDBC_DRIVER_FILENAME="postgresql-42.1.4.jar"
DOWNLOAD_RETRIES=5

# Install Java JDK8, Maven, PostgreSQL, Python-PIP, Ansible, Boto3, AWS-cli
sudo add-apt-repository ppa:webupd8team/java
sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y dist-upgrade
echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
sudo apt-get -qq -y install oracle-java8-set-default
sudo apt-get -y install maven postgresql python python-pip mc
sudo pip install --upgrade pip
sudo pip install awscli

# Export global variables
source "${PROJECT_DIR}/vagrant/developer/global_environment_awscli.sh"

# Change listen address binding to Vagrant ethernet interface to provide host machine connectivity to postgres through forwarded port
if [[ -z `echo ${DB_HOST} | grep amazon` ]]; then
    POSTGRES_CONF_PATH=`find /etc/postgresql -name "postgresql.conf"`
    sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '${DB_HOST}, 127.0.0.1'/g" ${POSTGRES_CONF_PATH}
    sudo sed -i "s/port = 5432/port = ${DB_PORT}/g" ${POSTGRES_CONF_PATH}

    # Add permission for DB_USER to connect to DB_NAME from host machine by IP from vagrant private_network
    PG_HBA_PATH=`find /etc/postgresql -name "pg_hba.conf"`
    sudo echo -e "host \t ${DB_NAME} \t ${DB_USER} \t\t ${ALLOWED_LAN} \t\t md5" >> ${PG_HBA_PATH}
    service postgresql restart
fi

# Create database and db_user
sudo -u postgres createdb ${DB_NAME}
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} to ${DB_USER};"

# Download Liquibase binaries and PostgreSQL JDBC driver
# -- by default wget makes 20 tries to download file if there is an error response from server (or use --tries=40 to increase retries amount).
# -- Exceptions are server responses CONNECTIONS_REFUSED and NOT_FOUND - in these cases wget will not retry download
mkdir -p ${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}
if [ ! -e "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/liquibase-bin.tar.gz" ]; then
#   wget "${LIQUIBASE_URL}" -O "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/liquibase-bin.tar.gz"
    until [  ${DOWNLOAD_RETRIES} -lt 0 ] || [ -e "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/liquibase-bin.tar.gz" ]; do
        aws s3 cp "s3://${BUCKET_NAME}/liquibase-3.5.3-bin.tar.gz" "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/liquibase-bin.tar.gz"
        let "DOWNLOAD_RETRIES--"
        sleep 15
    done

    if [ -e "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/liquibase-bin.tar.gz" ]; then
        tar -xzf "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/liquibase-bin.tar.gz" -C ${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}
    fi
fi

if [ ! -e "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/lib/postgresql-jdbc-driver.jar" ]; then
#   wget "${POSTGRES_JDBC_DRIVER_URL}" -O "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/lib/postgresql-jdbc-driver.jar"
    let DOWNLOAD_RETRIES=5
    until [  ${DOWNLOAD_RETRIES} -lt 0 ] || [ -e "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/lib/postgresql-jdbc-driver.jar" ]; do
        aws s3 cp "s3://${BUCKET_NAME}/postgresql-42.1.4.jar" "${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}/lib/postgresql-jdbc-driver.jar"
        let "DOWNLOAD_RETRIES--"
        sleep 15
    done
fi

# Update database using Liquibase
cd ${PROJECT_DIR}/${LIQUIBASE_BIN_DIR}
if [ ! -e liquibase.properties ]; then
    ln -s ../liquibase.properties liquibase.properties
fi
./liquibase update

echo "*********** INSTALLATION FINISHED. ************"
# sudo reboot

