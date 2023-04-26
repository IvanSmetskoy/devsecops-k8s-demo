def find_semgrep_breaches_in_project(project, directory) {
    sh "find ${project}  \\( -exec test -d '{}'/.git \\; \\) -exec git config --global --add safe.directory {} \\;"
    sh "find ${directory}/${project}  \\( -exec test -d '{}'/.git \\; \\) -exec semgrep --no-force-color -c ${directory}/semgrep-rules/java -l java -o {}/semgrep.log  {} \\;"
}

def remove_empty_semgrep_reports(project) {
    sh "find ${project} -name semgrep.log -type f -empty -delete"
}

pipeline {
  agent any

  environment {
    DOCKERHUB_CREDENTIALS = credentials('docker-hub')
    deploymentName = "devsecops"
    containerName = "devsecops-container"
    serviceName = "devsecops-svc"
    imageName = "ismetskoy/numeric-app:$GIT_COMMIT"
    applicationURL = "http://192.168.68.109/"
    applicationURI = "/increment/99"
  }

   parameters {
        booleanParam defaultValue: true, name: 'ENABLE_SEMGREP'
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

      stage('SAST Scan - SonarQube') {
        steps {
          withSonarQubeEnv('SonarQube') {
            sh "mvn clean verify sonar:sonar -Dsonar.projectKey=numeric-application -Dsonar.projectName='numeric-application' -Dsonar.host.url=http://192.168.68.109:9000"
          }
          timeout(time: 2, unit: 'MINUTES') {
            script {
              waitForQualityGate abortPipeline: true
            }
          }
        }
      }

     //stage('Semgrep') {
        //steps {
          //sh 'docker run --rm -v "$(pwd)/src" returntocorp/semgrep semgrep --config p/security-audit /src'
        //}
      //}

      stage('semgrep') {
            when {
                expression {
                    params.ENABLE_SEMGREP.toBoolean()
                }
            }
  
            agent {
                docker {
                    image 'returntocorp/semgrep'
                    reuseNode true
                    args '-i -u root --entrypoint='
                }
            }
  
            steps {
                script {
                    projects.each { project ->
                        stage("Checking ${project}") {
                            find_semgrep_breaches_in_project(project, env.WORKSPACE)
                            remove_empty_semgrep_reports(project)
                            archiveArtifacts artifacts: "${project}/**/semgrep.log", allowEmptyArchive: true
                        }
                    }
                }
            }
        }

      stage('Vulnerability Scan - Docker') {
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

    }

    post {
      always {
        sh 'docker logout'
        junit 'target/surefire-reports/*.xml'
        jacoco execPattern: 'target/jacoco.exec'
        dependencyCheckPublisher pattern: 'target/dependency-check-report.xml'
      }
    }
}
