pipeline {

  agent any

  environment {
    DOCKERHUB_CREDENTIALS = credentials('docker-hub')
    deploymentName = "devsecops"
    containerName = "devsecops-container"
    serviceName = "devsecops-svc"
    imageName = "ismetskoy/numeric-app:$GIT_COMMIT"
    applicationURL = "http://192.168.68.109"
    applicationURI = "/increment/99"
  }

  stages {
      stage('Build Artifact - Maven') {
            steps {
              sh "mvn clean package -DskipTests=true" 
              archive 'target/*.jar'
            }
        }   

      stage('Unit Test - Junit and Jacoco') {
            steps {
              sh "mvn test" 
            }
        }

      stage('SAST Scan') {
        steps {
          parallel(
            "SonarQube Scan": {
              withSonarQubeEnv('SonarQube') {
                sh "mvn clean verify sonar:sonar -Dsonar.projectKey=numeric-application -Dsonar.projectName='numeric-application' -Dsonar.host.url=http://192.168.68.109:9000"
              }
              timeout(time: 2, unit: 'MINUTES') {
                script {
                  waitForQualityGate abortPipeline: true
                }
              }
            },
            "Semgrep scan": {
              sh 'docker run -v "$(pwd):/src" --workdir /src returntocorp/semgrep-agent:v1 semgrep-agent --config p/ci --config p/security-audit --config p/secrets'
            }
          )
        }
      }

      stage('Dtrack') {
        steps {
          sh "bash deptrack.sh"
        }
      }

      stage('Vulnerability Scan - Docker'){
        steps {
          parallel(
            "Dependency Scan": {
              sh "mvn dependency-check:check"
            },
            "Aqua Trivy Scan": {
              sh "bash trivy-docker-image-scan.sh"
            },
            "OPA Conftest": {
              sh 'docker run --rm -v $(pwd):/project openpolicyagent/conftest test --policy opa-docker-security.rego Dockerfile'
            }
          )    
        }
      }

      stage('Docker Build and Push'){
        steps {
          sh 'echo $DOCKERHUB_CREDENTIALS_PSW | docker login -u $DOCKERHUB_CREDENTIALS_USR --password-stdin'
          sh 'printenv'
          sh 'sudo docker build -t ismetskoy/numeric-app:""$GIT_COMMIT"" .'
          sh 'docker push ismetskoy/numeric-app:""$GIT_COMMIT""'    
        }
      }

      stage('Vulnerability Scan - K8S'){
        steps {
          parallel(
            "OPA Scan": {
              sh 'docker run --rm -v $(pwd):/project openpolicyagent/conftest test --policy opa-k8s-security.rego k8s_deployment_service.yaml'
            },
            "KubeSec Scan": {
              sh "bash kubesec-scan.sh"
            },
            "Aqua Trivy Scan": {
              sh "bash trivy-k8s-scan.sh"
            }
          )  
        }
      }

      stage('Kubernetes Deployment - DEV'){
        steps {
          parallel(
            "Deployment": {
              withKubeConfig([credentialsId: 'kubeconfig']) {
                sh "bash k8s-deployment.sh"
              }
            },
            "Rollout Status": {
              withKubeConfig([credentialsId: 'kubeconfig']) {
                sh "bash k8s-deployment-rollout-status.sh"
              }
            }
          )
        }
      }

      stage('Integration Tests - DEV') {
        steps {
          script {
            try {
              withKubeConfig([credentialsId: 'kubeconfig']) {
                sh "bash integration-test.sh"
              }
            } catch (e) {
              withKubeConfig([credentialsId: 'kubeconfig']) {
                sh "kubectl -n default rollout undo deploy ${deploymentName}"
              }
              throw e
            }
          }
        }
      }

      stage('OWASP ZAP - DAST') {
        steps {
          withKubeConfig([credentialsId: 'kubeconfig']) {
            sh 'bash zap.sh'
          }
        }
      }

      stage('Promote to PROD?') {
        steps {
          timeout(time: 2, unit: 'DAYS') {
            input 'Do you want to Approve the Deployment to Production Environment/Namespace?'
          }
        }
      }

      stage('K8S CIS Benchmark') {
       steps {
         script {

           parallel(
             "Master": {
               sh "bash cis-master.sh"
             },
             "Etcd": {
               sh "bash cis-etcd.sh"
             },
             "Kubelet": {
               sh "bash cis-kubelet.sh"
             }
           )
         }
       }
     }

      stage('K8S Deployment - PROD') {
        steps {
          parallel(
            "Deployment": {
              withKubeConfig([credentialsId: 'kubeconfig']) {
                sh "sed -i 's#replace#${imageName}#g' k8s_PROD-deployment_service.yaml"
                sh "kubectl -n prod apply -f k8s_PROD-deployment_service.yaml"
              }
            },
            "Rollout Status": {
              withKubeConfig([credentialsId: 'kubeconfig']) {
                sh "bash k8s-PROD-deployment-rollout-status.sh"
              }
            }
          )
        }
      }



    }

    post {
      always {
        sh 'docker logout'
        junit 'target/surefire-reports/*.xml'
        jacoco execPattern: 'target/jacoco.exec'
        dependencyCheckPublisher pattern: 'target/dependency-check-report.xml'
        publishHTML([allowMissing: false, alwaysLinkToLastBuild: true, keepAll: true, reportDir: 'owasp-zap-report', reportFiles: 'zap_report.html', reportName: 'OWASP ZAP HTML Report', reportTitles: 'OWASP ZAP HTML Report', useWrapperFileDirectly: true])
      }
    }
}
