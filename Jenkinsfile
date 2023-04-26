pipeline {
  agent any

  environment {
    DOCKERHUB_CREDENTIALS = credentials('docker-hub')
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
      
      stage('Mutation Test - PIT') {
        steps {
          sh "mvn org.pitest:pitest-maven:mutationCoverage"
        }
        post {
          always {
            pitmutation mutationStatsFile: '**/target/pit-reports/**/mutations.xml'
          }
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

      stage('OWASP Dependency Check - Docker') {
        steps {
          sh "mvn dependency-check:check"
        }
      }

      stage('Docker Build and Push'){
        steps {
          sh 'echo $DOCKERHUB_CREDENTIALS_PSW | docker login -u $DOCKERHUB_CREDENTIALS_USR --password-stdin'
          sh 'printenv'
          sh 'docker build -t ismetskoy/numeric-app:""$GIT_COMMIT"" .'
          sh 'docker push ismetskoy/numeric-app:""$GIT_COMMIT""'    
        }
      }

      stage('Kubernetes Deployment - DEV'){
        steps {
          withKubeConfig([credentialsId: 'kubeconfig']) {
            sh "sed -i 's#replace#ismetskoy/numeric-app:${GIT_COMMIT}#g' k8s_deployment_service.yaml"
            sh "kubectl apply -f k8s_deployment_service.yaml" 
          }
        }
      }

    }

    post {
      always {
        sh 'docker logout'
        junit 'target/surefire-reports/*.xml'
        jacoco execPattern: 'target/jacoco.exec'
        pitmutation mutationStatsFile: '**/target/pit-reports/**/mutations.xml'
        dependencyCheckPublisher pattern: 'target/dependency-check-report.xml'
      }
    }
}
