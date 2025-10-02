pipeline {
    agent {
        ecs {
            inheritFrom 'build-slave-terraform'
        }
    }
    
    // Polling trigger - can also be configured in job settings
    triggers {
        pollSCM('* * * * *') // Poll every minute
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        // PR Validation Stages
        stage('PR Validation') {
            when {
                changeRequest()
            }
            stages {
                stage('Terraform Init - PR') {
                    steps {
                        sh 'terraform init -no-color'
                    }
                }
                
                stage('Terraform Validate - PR') {
                    steps {
                        sh 'terraform validate -no-color'
                    }
                }
                
                stage('Terraform Plan - PR') {
                    steps {
                        echo "Running Terraform Plan for PR #${env.CHANGE_ID}"
                        sh 'terraform plan -input=false -no-color'
                    }
                }
            }
        }
        
        // Main Branch Deployment Stages
        stage('Deploy from Main') {
            when {
                branch 'main'
            }
            stages {
                stage('Terraform Init - Main') {
                    steps {
                        sh 'terraform init -no-color'
                    }
                }
                
                stage('Terraform Plan - Main') {
                    steps {
                        sh 'terraform plan -input=false -no-color'
                    }
                }
                
                stage('Terraform Apply - Main') {
                    input {
                        message "Do you want to apply?"
                        ok "Confirm"
                    }
                    steps {
                        echo "Deploying to production"
                        sh 'terraform apply --auto-approve -no-color'
                    }
                }
            }
        }
    }
    
    post {
        success {
            script {
                if (env.CHANGE_ID) {
                    echo "✅ PR #${env.CHANGE_ID}: Terraform plan successful"
                } else if (env.BRANCH_NAME == 'main') {
                    echo "✅ Main branch: Terraform apply successful"
                }
            }
        }
        failure {
            echo "❌ Build failed! Check logs for details."
        }
    }
} 