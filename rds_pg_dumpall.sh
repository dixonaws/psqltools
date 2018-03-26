#!/bin/bash

#rds_host="mydbinstance.c15lzdctuff2.us-east-1.rds.amazonaws.com"
#rds_port="5432"
#log_group_name="aws_rds_postgres"
#log_stream_name="mydbinstance"
#region="us-east-1"
#db_username="master"

# precondition: s3_bucket exists, rds_host exists, user or instance running this script has IAM permissions to both
# postcondition: all databases on given rds_host are backed up to s3_bucket with a timestamp, using pg_dump with tar format
# parameters: this script should receive the following parameters:
# $1 - the RDS host 
# $2 - the RDS port to use
# $3 - the database username to use

backup_rds_instance() {
	# set the rds instance based on arguments to this function	
	local rds_host=$1
	local rds_port=$2
	local db_username=$3
	local s3_bucket=$4
	local log_group_name=$5
	local log_stream_name=$6
	local region=$7

	echo "Backing up databases on RDS instance $rds_host..."

	local dbname="db0"
	local paramstore_key=$rds_host
	local paramstore_key+="_"
	local paramstore_key+=$dbname
	local db_password=`aws ssm get-parameter --with-decryption --name "$paramstore_key" --region $region |jq -r '.Parameter.Value'`

	# query the RDS instance for a list of databases
	databases=$(psql --dbname="postgresql://$db_username:$db_password@$rds_host:$rds_port/postgres" --command="SELECT datname FROM pg_database WHERE datistemplate=false;" --no-align --tuples-only)

	# iterate through the list of datbases and back up each one with pg_dump
	for dbname in $databases; do

		datetimestring=$(date +%m-%d-%Y_%T%z)

		echo -n "Backing up $dbname... "

		# you can't backup the rdsadmin database on RDS, so we skip it
		if [ $dbname = "rdsadmin" ]
		then 
			echo "skipping rdsadmin"
			continue
		fi

		# get the database pasword from the paremeter store in AWS
		local paramstore_key=$rds_host
		local paramstore_key+="_"
		local paramstore_key+=$dbname
		local db_password=`aws ssm get-parameter --with-decryption --name "$paramstore_key" --region $region |jq -r '.Parameter.Value'`

		targetfilename=$dbname-$datetimestring-psql.tar

		# get the database password from the AWS Systems Manager paerameter store (your IAM user must have permissions to do this)
		db_password=`aws ssm get-parameter --with-decryption --name "$rds_host"_"$dbname" --region $region |jq -r '.Parameter.Value'`

		# stream the backup of each database directly to S3
		pg_dump --dbname="postgresql://$db_username:$db_password@$rds_host:$rds_port/$dbname" --format=tar | aws s3 cp - s3://$s3_bucket/$targetfilename --quiet

		# get the filesize in S3
		filesize=$(aws s3 ls s3://$s3_bucket/$targetfilename |awk '{print $3}')
		filesizemb=$(expr $filesize / 1024 / 1024)
		filesizekb=$(expr $filesize / 1024)
		echo "done ($targetfilename, $filesizekb KiB)"
			
		# log it
		# get the next sequence token (need this to write to a non-empty log stream)
		token=$(aws logs describe-log-streams --log-group-name $log_group_name --region $region |grep uploadSequenceToken |awk -F ":" '{print $2}')

		# strip off the quotes and comma from the string
		len=${#token}
		substr=$(expr $len - 5)
		token=${token:2:substr}

		aws logs put-log-events --log-group-name $log_group_name --log-stream-name $log_stream_name --log-events "timestamp=$(echo $(date +%s%N | cut -b1-13)),message='$dbname was backed up ($filesizekb KiB)'" --region us-east-1 --sequence-token $token > /dev/null

	done
}

usage() {
	echo "Usage: rds_pg_rumpall.sh [OPTION] -r rdsinstance -s s3bucket"
	echo "Backup all databses on RDSinstances to S3 using pg_dump"
	echo ""
	echo "Mandatory arguments:"
	echo "-r		a comma-separated list of RDS instances to backup; all databases on the instance will be backed up"
	echo "-b		the S3 bucket to store backups"
	echo "-g		the log group name"
	echo "-s		the stream name"
	echo "-e		the region name, e.g., us-east-1"
	echo ""
	echo "Optional arguments:"
	echo "-u		the username to use for each database on the instance(s), defaults to master"
	echo "-p		the port to use for the connection(s), defaults to 5432"
	echo ""
	echo "Example:"
	echo "rds_dumpall.sh -u master -p 5432 -r instance0,instance1,instancen -s dbtools -e us-east-1 -s mylogstream -g myloggroup"
	echo ""
	echo "See https://github.com/dixonaws/psqltools for source and more information"

	exit 1
}

##### Main

echo 'rds_pg_dumpall v1.0 (25 March 2018)'
echo ""

while getopts ":hr:u:p:b:s:g:e:" opt; do
	case ${opt} in
		h )
			usage
			;;
		r ) 
			rds_instances=$OPTARG
			number_of_instances=$(echo $rds_instances | awk --field-separator="," "{print NF}")
			echo "- backing up $number_of_instances RDS instances: $rds_instances"
			;;
		u )
			rds_username=$OPTARG
			echo "- using username: $rds_username"
			;;
		p ) 
			rds_port=$OPTARG
			echo "- using port: $rds_port"
			;;
		b ) 
			s3_bucket=$OPTARG
			echo "- using S3 bucket: $s3_bucket"
			;;
		g ) 
			log_group_name=$OPTARG
			echo "- using log group: $log_group_name"
			;;
		s ) 
			log_stream_name=$OPTARG
			echo "- using log stream: $log_stream_name"
			;;
		e ) 
			region=$OPTARG
			echo "- using region:  $region"
			;;
		: )
			echo "-$OPTARG requires an argument" 
			echo ""
			usage
			exit 1
			;;
		\? )
			echo "Invalid option: -$OPTARG"
			echo ""
			usage
			exit 1
			;;
	esac
done

if [ -z $region ]; then
	echo "Region is required, e.g., us-east-1"
	echo ""
	usage
fi


# backup each instance
for instance in $(echo $rds_instances | sed "s/,/ /g"); do 
	backup_rds_instance $instance $rds_port $rds_username $s3_bucket $log_group_name $log_stream_name $region
done



