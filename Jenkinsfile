pipeline{
    agent any
    tools {
            ansible 'ansible'
            terraform 'terraform'
    }

    environment {
        PATH=sh(script:"echo $PATH:/usr/local/bin", returnStdout:true).trim()
        AWS_REGION = "eu-north-1"
        AWS_ACCOUNT_ID=sh(script:'export PATH="$PATH:/usr/local/bin" && aws sts get-caller-identity --query Account --output text', returnStdout:true).trim()
        ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        APP_REPO_NAME = "diana-repo/final-project"
    }

    stages {
        stage('Prepare') {
            steps {
                script {
                    // Retrieve the instance ID of the current EC2 instance
                    def instanceId = sh(script: "curl http://169.254.169.254/latest/meta-data/instance-id", returnStdout: true).trim()
                    // Retrieve the private IP address of the current instance
                    def privateIp = sh(script: "aws ec2 describe-instances --instance-ids ${instanceId} --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text", returnStdout: true).trim()
                    def publicIp = sh(script: "aws ec2 describe-instances --instance-ids ${instanceId} --query 'Reservations[*].Instances[*].PublicIpAddress' --output text", returnStdout: true).trim()
                    // Set the private IP as an environment variable
                    env.JENKINS_PRIVATE_IP = privateIp
                    echo "PRIVATE IP: ${privateIp}"
                    env.JENKINS_PUBLIC_IP = publicIp
                    echo "PUBLIC IP: ${publicIp}"
                    def cidrIps = privateIp.split("\\s+").collect { it + "/32" }
                    env.JENKINS_PRIVATE_IPS = cidrIps.join(",")
                    echo "CIDR IP's: ${cidrIps}"
                    def cidrPublicIps = publicIp.split("\\s+").collect { it + "/32" }
                    env.JENKINS_PUBLIC_IPS = cidrPublicIps.join(",")
                    echo "CIDR PUBLIC IP's: ${cidrPublicIps}"
                }
            }
        }
        stage('Fetch VPC ID') {
            steps {
                script {
                    // Fetch the VPC ID for the 'prod' environment
                    def vpcId = sh(
                        script: "aws ec2 describe-vpcs --filters 'Name=tag:Environment,Values=prod' --query 'Vpcs[0].VpcId' --output text",
                        returnStdout: true
                    ).trim()
                    echo "VPC ID: ${vpcId}"

                    // Set environment variable for VPC ID
                    env.VPC_ID = vpcId
                }
            }
        }
        stage('Fetch Subnet IDs') {
            steps {
                script {
                    // Fetch Public Subnet ID                    // Assuming you want to target a specific availability zone, adjust as needed                    def availabilityZone = 'us-north-1a' // Example, adjust to your AZ
                    def publicSubnetId = sh(
                        script: "aws ec2 describe-subnets --filters 'Name=vpc-id,Values=${env.VPC_ID}' 'Name=tag:Name,Values=prod-public-subnet' --query 'Subnets[0].SubnetId' --output text",
                        returnStdout: true
                    ).trim()
                    echo "Public Subnet ID: ${publicSubnetId}"
                    env.PUBLIC_SUBNET_ID = publicSubnetId

                    // Fetch Private Subnet ID
                    def privateSubnetId = sh(
                        script: "aws ec2 describe-subnets --filters 'Name=vpc-id,Values=${env.VPC_ID}' 'Name=tag:Name,Values=prod-private-subnet' --query 'Subnets[0].SubnetId' --output text",
                        returnStdout: true
                    ).trim()
                    echo "Private Subnet ID: ${privateSubnetId}"
                    env.PRIVATE_SUBNET_ID = privateSubnetId
                }
            }
        }
        stage('Create Infrastructure for the App') {
            steps {
                echo 'Creating Infrastructure for the App on AWS Cloud'
                sh 'terraform init'
                sh "terraform apply --auto-approve -var 'jenkins_private_ip=[\"${env.JENKINS_PRIVATE_IPS.replace(',', '\",\"')}\"]' -var 'jenkins_public_ip=[\"${env.JENKINS_PUBLIC_IPS.replace(',', '\",\"')}\"]' -var 'public_subnet_id=${ env.PUBLIC_SUBNET_ID}' -var 'vpc_id=${env.VPC_ID}'"
            }
        }
        stage('Create ECR Repo') {
            steps {
                echo 'Creating ECR Repo for App'
                sh '''
                aws ecr describe-repositories --region ${AWS_REGION} --repository-name ${APP_REPO_NAME} || \
                aws ecr create-repository \
                    --repository-name ${APP_REPO_NAME} \
                    --image-scanning-configuration scanOnPush=false \
                    --image-tag-mutability MUTABLE \
                    --region ${AWS_REGION}
                '''
            }
        }

        stage('Build App Docker Image') {
            steps {
                echo 'Building App Image'
                script {
                    env.GITEA1_IP = sh(script: 'terraform output -raw gitea1_ip', returnStdout:true).trim()
                    env.GITEA2_IP = sh(script: 'terraform output -raw gitea2_ip', returnStdout:true).trim()
                    env.DB_HOST = sh(script: 'terraform output -raw postgresql_private_ip', returnStdout:true).trim()
                    env.DB_NAME = sh(script: 'aws --region=eu-north-1 ssm get-parameters --names "gitea_db_name" --with-decryption --query "Parameters[*].{Value:Value}" --output text', returnStdout:true).trim()
                    env.DB_USER = sh(script: 'aws --region=eu-north-1 ssm get-parameters --names "gitea_db_user" --with-decryption --query "Parameters[*].{Value:Value}" --output text', returnStdout:true).trim()
                    env.DB_PASSWORD = sh(script: 'aws --region=eu-north-1 ssm get-parameters --names "gitea_db_password" --with-decryption --query "Parameters[*].{Value:Value}" --output text', returnStdout:true).trim()
                }
                sh 'echo ${DB_HOST}'
                sh 'echo ${GITEA1_IP}'
                sh 'echo ${GITEA2_IP}'
                sh 'echo ${DB_NAME}'
                sh 'echo ${DB_PASSWORD}'

                sh 'docker build --force-rm -t "$ECR_REGISTRY/$APP_REPO_NAME:postgres" -f ./postgresql/dockerfile-postgresql .'
                sh 'docker build --force-rm -t "$ECR_REGISTRY/$APP_REPO_NAME:gitea" -f ./gitea/dockerfile-gitea .'
                sh 'docker image ls'
            }
        }

        stage('Push Image to ECR Repo') {
            steps {
                echo 'Pushing App Image to ECR Repo'
                sh 'aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin "$ECR_REGISTRY"'
                sh 'docker push "$ECR_REGISTRY/$APP_REPO_NAME:postgres"'
                sh 'docker push "$ECR_REGISTRY/$APP_REPO_NAME:gitea"'
            }
        }
        stage('wait the instance') {
            steps {
                script {
                    echo 'Waiting for the instance'
                    id = sh(script: 'aws ec2 describe-instances --filters Name=tag-value,Values=postgresql Name=instance-state-name,Values=running --query Reservations[*].Instances[*].[InstanceId] --output text',  returnStdout:true).trim()
                    sh 'aws ec2 wait instance-status-ok --instance-ids $id'
                }
            }
        }

        stage('Deploy the App') {
            steps {
                echo 'Deploy the App'
                sh 'ls -l'
                sh 'ansible --version'
                sh 'ansible-inventory --graph'
                ansiblePlaybook credentialsId: 'jenkins-private-key', disableHostKeyChecking: true, installation: 'ansible', inventory: 'inventory_aws_ec2.yml', playbook: 'docker_project.yml',
                    extraVars: [
                        db_host: "${env.DB_HOST}",
                        db_name: "${env.DB_NAME}",
                        db_user: "${env.DB_USER}"
                    ]
            }
        }
        stage('Destroy the infrastructure'){
            steps{
                timeout(time:30, unit:'MINUTES'){
                    input message:'Approve terminate'
                }
                sh """
                docker image prune -af
                terraform destroy --auto-approve
                aws ecr delete-repository \
                  --repository-name ${APP_REPO_NAME} \
                  --region ${AWS_REGION} \
                  --force
                """
            }
        }
    }
    post {
        always {
            echo 'Deleting all local images'
            sh 'docker image prune -af'
        }


        failure {

            echo 'Delete the Image Repository on ECR due to the Failure'
            sh """
                terraform destroy --auto-approve
                aws ecr delete-repository \
                --repository-name ${APP_REPO_NAME} \
                --region ${AWS_REGION}\
                --force
                """
            echo 'Deleting Terraform Stack due to the Failure'
                sh 'terraform destroy --auto-approve'
        }
    }
}
