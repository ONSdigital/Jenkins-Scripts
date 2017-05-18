To bootstrap the Jenkins instance deployer:

$ ./jenkins/jenkins_deploy_cf.sh -n jenkins-deploy -m 2048M -d 2048M -C 'git@bitbucket.org:userix/jenkins_deploy.git' \
	-u '$CF_ADMIN_USER' -s '$SPACE' -o '$ORGANISATION' -p '$CF_ADMIN_PASSWORD'" -a '$CF_API_ENDPOINT' -X
