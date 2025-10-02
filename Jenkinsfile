pipeline {
    agent {
        ecs {
            inheritFrom 'build-slave-terraform'
        }
    }
    
    triggers {
        pollSCM('* * * * *')
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                
                // Enhanced debug information
                script {
                    echo "=== DEBUG BRANCH INFO ==="
                    echo "BRANCH_NAME: ${env.BRANCH_NAME}"
                    echo "GIT_BRANCH: ${env.GIT_BRANCH}"
                    echo "CHANGE_ID: ${env.CHANGE_ID}"
                    echo "CHANGE_TARGET: ${env.CHANGE_TARGET}"
                    
                    // Check if this looks like a PR branch
                    def isPR = env.BRANCH_NAME?.contains('pull-request') || 
                              env.BRANCH_NAME?.contains('PR-') ||
                              env.GIT_BRANCH?.contains('pull-request') ||
                              env.CHANGE_ID != null
                    
                    echo "Detected as PR: ${isPR}"
                    echo "========================"
                }
            }
        }
        
        // PR Validation Stages - Enhanced detection
        stage('PR Validation') {
            when {
                anyOf {
                    changeRequest() // Standard PR detection
                    expression { 
                        return env.BRANCH_NAME?.contains('pull-request') || 
                               env.BRANCH_NAME?.contains('PR-') ||
                               env.GIT_BRANCH?.contains('pull-request')
                    }
                }
            }
            stages {
                stage('Terraform Init - PR') {
                    steps {
                        echo "✅ Running PR validation for: ${env.BRANCH_NAME}"
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
                        echo "Running Terraform Plan for PR: ${env.CHANGE_ID ?: env.BRANCH_NAME}"
                        sh 'terraform plan -input=false -no-color'
                    }
                }
            }
        }
        
        // Main Branch Deployment Stages
        stage('Deploy from Main') {
            when {
                anyOf {
                    branch 'main'
                    expression { 
                        return env.BRANCH_NAME == 'main' || 
                               env.GIT_BRANCH == 'origin/main' ||
                               (env.BRANCH_NAME?.contains('main') && !env.BRANCH_NAME?.contains('pull-request'))
                    }
                }
            }
            stages {
                stage('Terraform Init - Main') {
                    steps {
                        echo "✅ Deploying from main branch!"
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
        
        // Debug stage for unmatched branches
        stage('Debug - Unmatched Branch') {
            when {
                not {
                    anyOf {
                        branch 'main'
                        changeRequest()
                        expression { 
                            return env.BRANCH_NAME?.contains('pull-request') || 
                                   env.BRANCH_NAME?.contains('main')
                        }
                    }
                }
            }
            steps {
                echo "⚠️ This branch didn't match any deployment conditions"
                echo "Branch: ${env.BRANCH_NAME}"
                echo "Git Branch: ${env.GIT_BRANCH}"
                echo "This might be a feature branch or unrecognized PR pattern"
            }
        }
    }
}