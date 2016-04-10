#docker network create -d bridge i2b2-net
BASE=$1
DOCKER_HOME=$BASE/local/docker

DIP=$2

docker network create i2b2-net

echo "PWD;$(pwd)"

	source $BASE/scripts/install/install.sh $BASE
	check_homes_for_install $BASE
	download_i2b2_source $BASE
	unzip_i2b2core $BASE

#Docker App Path
APP=i2b2-wildfly
DAP=$DOCKER_HOME/$APP
if [ -d $DAP ]; then
	echo "found $DAP"
else
	mkdir -p "$DAP" & echo "created $DAP"
	
	mkdir -p $DAP/jbh
	
	cp -rv $BASE/conf/docker/$APP/* $DAP

	
	JBOSS_HOME=$DAP/jbh/
	echo "JBOSS_HOME=$JBOSS_HOME"
	copy_axis_to_wildfly $JBOSS_HOME	
	compile_i2b2core $BASE $JBOSS_HOME 
#run_wildfly $BASE
	
	
	cd  $DAP/jbh/standalone/deployments/
	tar -cvjf i2b2-war.tar.bz2  i2b2.war/*
	
	cd  $DAP/jbh/standalone
	for x in $(find -iname *.xml); do
		echo $x
		sed -i  s/localhost/$DIP/ "$x"
		sed -i  s/127.0.0.1/$DIP/ "$x"
		sed -i  s/9090/8080/ "$x"
	done
	for x in $(find -iname *.properties); do
		echo $x
		sed -i  s/localhost/$DIP/ "$x"
		sed -i  s/127.0.0.1/$DIP/ "$x"
		sed -i  s/9090/8080/ "$x"
	done
	cd $BASE


	docker stop $APP;docker rm $APP; docker rmi i2b2/wildfly
	docker build  -t i2b2/wildfly $DAP/
	docker run -d -p 8080:8080 -p 9990:9990 --net i2b2-net --name $APP i2b2/wildfly
	
	#docker run -it jboss/wildfly /opt/jboss/wildfly/bin/domain.sh -b 0.0.0.0 -bmanagement 0.0.0.0

fi


APP=i2b2-web
DAP="$DOCKER_HOME/$APP"

if [ -d $DAP ]; then
	echo "found $DAP"
else
	mkdir -p "$DAP" && echo "created $DAP"
	echo "BASE:$BASE DIP:$DIP DAP:$DAP"
	source $BASE/scripts/install/centos_sudo_install.sh $BASE
	copy_webclient_dir $BASE $DIP $DAP

	cp -rv $BASE/conf/httpd/* $DAP
	cp -rv $BASE/conf/docker/$APP/* $DAP
	sed -i  s/9090/8080/ $DAP/i2b2_proxy.conf
	sed -i  s/localhost/$DIP/ $DAP/i2b2_proxy.conf

	docker stop $APP;docker rm $APP; docker rmi i2b2/web
	docker build  -t i2b2/web $DAP/
	docker run -d  -p 443:443 -p 80:80 --net i2b2-net --name i2b2-web i2b2/web
fi


APP=i2b2-pg
DAP="$DOCKER_HOME/$APP"


if [ -d $DAP ]; then
	echo "found $DAP"
else
	mkdir -p "$DAP" & echo "created $DAP"
	docker stop $APP;docker rm $APP; docker rmi i2b2/pg
	
	docker run --net i2b2-net --name $APP -d -p 5432:5432 -v /var/lib/pgsql -e 'DB_USER=i2b2' -e 'DB_PASS=pass' -e 'DB_NAME=i2b2' centos/postgresql
	docker ps
	#DIP=$(docker inspect --format '{{ index .NetworkSettings "Networks" "i2b2-net" "IPAddress"}} ' i2b2-pg)
	source $BASE/scripts/postgres/load_data.sh $(pwd) 

	USERT=" -U i2b2 -d i2b2 -h $DIP ";
	echo "USERT=$USERT"
	#echo "\dt+;"|psql $USERT
	sleep 5
	export PGPASSWORD=pass;echo "\dt+;"|psql -h 192.168.99.100 -U i2b2 -d i2b2
	create_db_schema $(pwd) "$USERT";
	export PGPASSWORD=demouser;
        load_demo_data $(pwd) " -h $DIP -d i2b2 " $DIP
fi


