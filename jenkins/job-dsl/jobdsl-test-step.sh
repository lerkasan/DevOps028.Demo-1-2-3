#!/usr/bin/env bash

function get_from_parameter_store {
    aws ssm get-parameters --names $1 --with-decryption --output text | awk '{print $4}'
}

function download_from_s3 {
    let RETRIES=$3
    until [ ${RETRIES} -lt 0 ] || [ -e "$2" ]; do
        aws s3 cp $1 $2
        let "RETRIES--"
        sleep 5
    done
    if [ ! -e "$2" ]; then
        echo "An error occurred during downloading file by URL $1"
        exit 1
    fi
}

export AWS_DEFAULT_REGION="us-west-2"
export AWS_SECRET_ACCESS_KEY=`get_from_parameter_store "SECRET_ACCESS_KEY"`
export AWS_ACCESS_KEY_ID=`get_from_parameter_store "ACCESS_KEY_ID"`

export DB_NAME=`get_from_parameter_store "DB_NAME"`
export DB_USER=`get_from_parameter_store "DB_USER"`
export DB_PASS=`get_from_parameter_store "DB_PASS"`
export LOGIN_HOST="localhost"

TEST_DB_INSTANCE_ID="demo1-test"
DB_INSTANCE_ID="demo1"
DB_INSTANCE_CLASS="db.t2.micro"
DB_ENGINE="postgres"

BUCKET_NAME="ansible-demo1"
LIQUIBASE_BIN_DIR="${WORKSPACE}/liquibase/bin"
LIQUIBASE_FILENAME="liquibase-3.5.3-bin.tar.gz"
LIQUIBASE_URL="s3://${BUCKET_NAME}/${LIQUIBASE_FILENAME}"
LIQUIBASE_PROPERTIES_TEMPLATE="${WORKSPACE}/liquibase/liquibase.properties.template"
LIQUIBASE_PROPERTIES="${WORKSPACE}/liquibase/liquibase.properties"

POSTGRES_JDBC_DRIVER_FILENAME="postgresql-42.1.4.jar"
POSTGRES_JDBC_DRIVER_URL="s3://${BUCKET_NAME}/${POSTGRES_JDBC_DRIVER_FILENAME}"

DOWNLOAD_RETRIES=5

# Create test database instance if needed
EXISTING_TEST_DB_INSTANCE_INFO=`aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address,Endpoint.Port,DBInstanceStatus]' \
--output text | grep ${TEST_DB_INSTANCE_ID} | grep -v -e terminated -e shutting-down`
if [[ -z ${EXISTING_TEST_DB_INSTANCE_INFO} ]]; then
    aws rds create-db-instance --db-instance-identifier ${TEST_DB_INSTANCE_ID} --db-instance-class ${DB_INSTANCE_CLASS} --engine ${DB_ENGINE} \
    --backup-retention-period 0 --storage-type gp2 --allocated-storage 5 --db-name ${DB_NAME} --master-username ${DB_USER} --master-user-password ${DB_PASS}
    aws rds wait db-instance-available --db-instance-identifier ${TEST_DB_INSTANCE_ID}
fi

# Start test database instance if needed
EXISTING_TEST_DB_INSTANCE_INFO=`aws rds describe-db-instances --db-instance-identifier ${TEST_DB_INSTANCE_ID} \
--query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address,Endpoint.Port,DBInstanceStatus]' --output text`
DB_STATUS=`echo ${EXISTING_TEST_DB_INSTANCE_INFO} | awk '{print $4}'`
if [[ ${DB_STATUS} == "stopped" ]]; then
    aws rds start-db-instance --db-instance-identifier ${TEST_DB_INSTANCE_ID}
    aws rds wait db-instance-available --db-instance-identifier ${TEST_DB_INSTANCE_ID}
fi

# Prepare test database
export DB_HOST=`echo ${EXISTING_TEST_DB_INSTANCE_INFO} | awk '{print $2}'`
export DB_PORT=`echo ${EXISTING_TEST_DB_INSTANCE_INFO} | awk '{print $3}'`

# Download Liquibase binaries and PostgreSQL JDBC driver
mkdir -p ${LIQUIBASE_BIN_DIR}
if [ ! -e "${LIQUIBASE_BIN_DIR}/${LIQUIBASE_FILENAME}" ]; then
    download_from_s3 "${LIQUIBASE_URL}" "${LIQUIBASE_BIN_DIR}/${LIQUIBASE_FILENAME}" ${DOWNLOAD_RETRIES}
    if [ -e "${LIQUIBASE_BIN_DIR}/${LIQUIBASE_FILENAME}" ]; then
        tar -xzf "${LIQUIBASE_BIN_DIR}/${LIQUIBASE_FILENAME}" -C "${LIQUIBASE_BIN_DIR}"
    fi
fi

if [ ! -e "${LIQUIBASE_BIN_DIR}/lib/${POSTGRES_JDBC_DRIVER_FILENAME}" ]; then
    download_from_s3 "${POSTGRES_JDBC_DRIVER_URL}" "${LIQUIBASE_BIN_DIR}/lib/${POSTGRES_JDBC_DRIVER_FILENAME}" ${DOWNLOAD_RETRIES}
fi

# Update test database using Liquibase
sed "s/%LOGIN_HOST%/${LOGIN_HOST}/g" ${LIQUIBASE_PROPERTIES_TEMPLATE} |
    sed "s/%DB_HOST%/${DB_HOST}/g" |
    sed "s/%DB_PORT%/${DB_PORT}/g" |
    sed "s/%DB_NAME%/${DB_NAME}/g" |
    sed "s/%DB_USER%/${DB_USER}/g" |
    sed "s/%DB_PASS%/${DB_PASS}/g" > ${LIQUIBASE_PROPERTIES}

echo "Test database URL ${DB_HOST}:${DB_PORT}"
cd ${LIQUIBASE_BIN_DIR}
./liquibase --changeLogFile=../changelogs/changelog-main.xml --defaultsFile=../liquibase.properties update