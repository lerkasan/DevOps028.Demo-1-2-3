#!groovy

pipeline {
    agent {
        label 'slave-node'
    }
    tools {
        jdk 'oracle-jdk8u144-linux-x64'
        maven "maven-3.5.0"
    }
    options {
        timestamps()
    }
    parameters {
        string(name: 'bucket_name', defaultValue: 'demo2-ssa', description: 'Bucket with JDK, liquibase binaries and artifact for Demo2')
        string(name: 'rds_identifier', defaultValue: 'demo2-rds', description: 'RDS instance identifier for Demo2')
        string(name: 'elb_name', defaultValue: 'demo2-elb', description: 'Classic load balancer name for Demo2')
        string(name: 'autoscalegroup_name', defaultValue: 'demo2-autoscalegroup', description: 'Autoscaling group name for Demo2')
        string(name: 'aws_ecr_url', defaultValue: 'https://370535134506.dkr.ecr.us-west-2.amazonaws.com/demo3', description: 'AWS Docker Container Registry URL')
    }
    environment {
        AWS_DEFAULT_REGION="us-west-2"
        AWS_SECRET_ACCESS_KEY = sh(
                script: "export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} && aws ssm get-parameter --name jenkins_secret_access_key --with-decryption --output text | awk '{print \$4}'",
                returnStdout: true
        ).trim()
        AWS_ACCESS_KEY_ID = sh(
                script: "export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} && aws ssm get-parameter --name jenkins_access_key_id --with-decryption --output text | awk '{print \$4}'",
                returnStdout: true
        ).trim()

        TF_VAR_db_name = sh(
                script: "export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} && aws ssm get-parameter --name demo2_db_name --with-decryption --output text | awk '{print \$4}'",
                returnStdout: true
        ).trim()

        TF_VAR_db_user = sh(
                script: "export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} && aws ssm get-parameter --name demo2_db_user --with-decryption --output text | awk '{print \$4}'",
                returnStdout: true
        ).trim()

        TF_VAR_db_pass = sh(
                script: "export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} && aws ssm get-parameter --name demo2_db_pass --with-decryption --output text | awk '{print \$4}'",
                returnStdout: true
        ).trim()

        TF_VAR_aws_region="${AWS_DEFAULT_REGION}"
        TF_VAR_availability_zone1="${AWS_DEFAULT_REGION}a"
        TF_VAR_availability_zone2="${AWS_DEFAULT_REGION}b"
        TF_VAR_availability_zone3="${AWS_DEFAULT_REGION}c"
        TF_VAR_bucket_name="${params.bucket_name}"
        TF_VAR_rds_identifier="${params.rds_identifier}"
        TF_VAR_elb_name="${params.elb_name}"
        TF_VAR_autoscalegroup_name="${params.autoscalegroup_name}"
        TF_VAR_max_servers_in_autoscaling_group=3
        TF_VAR_webapp_port=9000
        TF_VAR_health_check_path="/login"
    }
    stages {
        stage('Checkout') {
            steps {
                echo "Cleaning workspace ..."
                cleanWs()
                echo "Checkout master branch to workspace folder and checkout jenkins branch to subfolder 'jenkins'"
                checkout(
                        [$class: 'GitSCM',
                         branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false,
                         browser: [$class: 'GithubWeb', repoUrl: 'https://github.com/lerkasan/DevOps028.git'],
                         extensions: [[$class: 'CleanBeforeCheckout']],
                         gitTool: 'git',
                         submoduleCfg: [],
                         userRemoteConfigs: [[url: 'https://github.com/lerkasan/DevOps028.git', credentialsId: 'github_lerkasan']]
                        ])
                checkout(
                        poll: false,
                        changelog: false,
                        scm: [$class: 'GitSCM',
                         branches: [[name: '*jenkins']], doGenerateSubmoduleConfigurations: false,
                         extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'jenkins'], [$class: 'IgnoreNotifyCommit']],
                         gitTool: 'git',
                         submoduleCfg: [],
                         userRemoteConfigs: [[url: 'https://github.com/lerkasan/DevOps028.git', credentialsId: 'github_lerkasan']]
                        ])
            }
        }
        stage("Prepare AWS infrastructure, test and build ") {
            parallel  {
                // Let's create here AWS infrastructure and assume that it is our production environment that has already existed before running this pipeline.
                // This stage should be ommited in real situation when we already have existing production environment
                stage("Prepare AWS infrastructure") {
                    steps {
                        echo "Preparing AWS infrastructure ..."
                        sh "chmod +x jenkins/jenkins/pipeline/*.sh"
                        sh "jenkins/jenkins/pipeline/prepare-infra.sh"
                    }
                }
                stage("Test and build")  {
                    steps {
                        sh "javac -version"
                        echo "Testing project"
                        sh "mvn clean test"
                        echo "Building jar ..."
                        sh "mvn clean package"
                    }
                    post {
                        success {
                            archiveArtifacts artifacts: 'target/*.jar', onlyIfSuccessful: true
                            echo "Copying artifact to S3 bucket ..."
                            sh 'ARTIFACT_FILENAME=`ls ${WORKSPACE}/target | grep jar | grep -v original` && ' +
                               'aws s3 cp "${WORKSPACE}/target/${ARTIFACT_FILENAME}" "s3://${TF_VAR_bucket_name}/artifacts/${ARTIFACT_FILENAME}" && ' +
                               'aws ssm put-parameter --name demo2_artifact_filename --value="${ARTIFACT_FILENAME}" --type String --overwrite'
                        }
                    }
                }
            }
        }
        stage("Build docker image") {
            environment {
                DB_HOST = sh(script: "aws rds describe-db-instances --db-instance-identifier ${TF_VAR_rds_identifier} " +
                        "--query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Address,DBInstanceStatus]' --output text | awk '{print \$2}'",
                        returnStdout: true
                ).trim()
                DB_PORT = sh(script: "aws rds describe-db-instances --db-instance-identifier ${TF_VAR_rds_identifier} " +
                        "--query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Port,DBInstanceStatus]' --output text | awk '{print \$2}'",
                        returnStdout: true
                ).trim()
                ARTIFACT_FILENAME = sh(script: "ls ${WORKSPACE}/target | grep jar | grep -v original",
                        returnStdout: true
                ).trim()
            }
            steps {
                echo "Building docker image ..."
                sh "cp ${WORKSPACE}/target/${ARTIFACT_FILENAME} ."
                script {
                        samsaraImage = docker.build("demo3:samsara-${env.BUILD_ID}", "--build-arg DB_HOST=${DB_HOST} --build-arg DB_PORT=${DB_PORT} --build-arg DB_NAME=${TF_VAR_db_name}, " +
                                                    "--build-arg DB_USER=${TF_VAR_db_user} --build-arg DB_PASS=${TF_VAR_db_pass} --build-arg ARTIFACT_FILENAME=${ARTIFACT_FILENAME} .")
                }
            }
        }
        stage("Push docker image to AWS ECR") {
            environment {
                AWS_ECR_URL="${params.aws_ecr_url}"
            }
            steps {
                echo "Pushing docker image to AWS ECR ${AWS_ECR_URL} ..."
                sh 'docker_pass=`aws ecr get-login --no-include-email --region us-west-2 | awk \'{print \$6}\'` && ecr_url=`echo "${AWS_ECR_URL}"` && docker login -u AWS -p "${docker_pass}" "${ecr_url}"'
//              sh 'docker_login_command=`aws ecr get-login --no-include-email --region us-west-2` && "${docker_login_command}"'
                script {
                    docker.withRegistry("${params.aws_ecr_url}") {
//                  docker.withRegistry("${params.aws_ecr_url}", 'ecr:us-west-2:demo3-aws-ecr-credentials') {
                        docker.image("demo3:samsara-${env.BUILD_ID}").push()
                    }
                }
            }
        }
        stage("Deploy") {
            steps {
                echo "Deploying ..."
                sh "jenkins/jenkins/pipeline/rolling-update-instances.sh"
            }
            post {
                success {
                    sh "jenkins/jenkins/pipeline/check-webapp-response.sh"
                }
            }
        }
    }
    post {
        success {
            emailext body: '${BUILD_LOG_REGEX, regex="Webapp endpoint", showTruncatedLines=false}',
                    subject: 'Web application Samsara was deployed',
                    to: 'lerkasan@gmail.com'
        }
        failure {
            emailext attachLog: true,
                    body: 'Build log is attached.',
                    subject: 'Web application Samsara deploy failed',
                    to: 'lerkasan@gmail.com'
        }
    }
}
