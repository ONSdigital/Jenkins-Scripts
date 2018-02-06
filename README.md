To bootstrap the Jenkins instance deployer:

$ ./jenkins/jenkins\_deploy\_cf.sh -n jenkins-deploy -m 2048M -d 2048M -C https://github.com/ONSdigital/Jenkins-Scripts \
	-u '$CF\_ADMIN\_USER' -s '$SPACE' -o '$ORGANISATION' -p '$CF\_ADMIN\_PASSWORD'" -a '$CF\_API\_ENDPOINT' -X
