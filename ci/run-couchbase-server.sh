#!/bin/bash

if [ "$MATRIX_JOB_TYPE" == "TEST" ]; then
    while sleep 9m; do echo -e '\n=====[ Gradle build is still running ]====='; done &

    echo "Pulling Couchbase docker image..."
    docker pull couchbase/server:4.6.4

    echo "Running Couchbase docker image..."
    docker run -d --name couchbase -p 8091-8094:8091-8094 -p 11210:11210 couchbase/server:4.6.4

    docker ps | grep "couchbase"
    retVal=$?
    if [ $retVal == 0 ]; then
        echo "Couchbase docker image is running."
    else
        echo "Couchbase docker image failed to start."
        exit $retVal
    fi

    echo "Waiting for Couchbase server to come online..."
    until $(curl --output /dev/null --silent --head --fail http://localhost:8091); do
        printf '.'
        sleep 1
    done
    
    echo -e "\n*************************************************************"
    echo -e "Setting default memory quota for the pool"
    echo -e "*************************************************************"
    curl -X POST http://localhost:8091/pools/default -d memoryQuota=512

    echo -e "\n*************************************************************"
    echo -e "Initialize node..."
    echo -e "*************************************************************"
    curl -X POST http://localhost:8091/nodes/self/controller/settings -d path=/opt/couchbase/var/lib/couchbase/data -d index_path=/opt/couchbase/var/lib/couchbase/data

    echo -e "*************************************************************"
    echo -e "Rename node..."
    echo -e "*************************************************************"
    curl -v -X POST http://localhost:8091/node/controller/rename -d hostname=127.0.0.1

    echo -e "\n*************************************************************"
    echo -e "Setting cluster services..."
    echo -e "*************************************************************"
    curl -X POST http://localhost:8091/node/controller/setupServices -d 'services=kv%2Cn1ql%2Cindex'

    echo -e "\n*************************************************************"
    echo -e "Setup Administrator username and password..."
    echo -e "*************************************************************"
    curl -X POST http://localhost:8091/settings/web -d password=password -d username=admin -d port=8091

    echo -e "\n*************************************************************"
    echo -e "Creating default Couchbase bucket..."
    echo -e "*************************************************************"
    curl -u admin:password -v -X POST -d 'name=default' -d 'bucketType=couchbase' -d 'ramQuotaMB=120' -d 'authType=none' -d 'proxyPort=11216' http://localhost:8091/pools/default/buckets

    echo -e "\n*************************************************************"
    echo -e "Creating index settings..."
    echo -e "*************************************************************"
    curl -X POST -u 'admin:password' 'http://localhost:8091/settings/indexes' -d 'indexerThreads=0' -d 'logLevel=info' -d 'maxRollbackPoints=5' -d 'memorySnapshotInterval=200' -d 'stableSnapshotInterval=5000' -d 'storageMode=forestdb'
    sleep 2
    curl -X POST http://localhost:8093/query/service -d 'statement=CREATE INDEX accounts_idx ON default(username)' -d 'namespace=default'
    sleep 1
    curl -X POST http://localhost:8093/query/service -d 'statement=CREATE PRIMARY INDEX `primary-idx` ON `default` USING GSI;' -d 'namespace=default'
    sleep 1

    echo -e "\n*************************************************************"
    echo -e "Creating document/accounts..."
    echo -e "*************************************************************"
    curl -X POST http://localhost:8093/query/service -d 'statement=INSERT INTO `default` (KEY,VALUE) VALUES("accounts", {"username": "casuser", "psw": "Mellon", "firstname": "CAS", "lastname":"User"})'

fi
