# TAP Agent

This experimental scheduler (with a somewhat misleading name) expose a push based rest API for scheduling and retriving experiment results on a monroe node. 
The scheduler/agent listen by default on port 8080 on all interfaces with a self-signed certificate. 
To deploy, start, stop and get the experiment results a valid api key is needed, default ```$3cr3t_Pa$$w0rd!```

## Howto Build (need to have docker,bash and internet connection)
1. clone and cd into repo directory  
2. ```./build.sh```

## Howto install 
1. Install Debian Stretch and monroe-experiment-core > 0.2.0 (https://github.com/MONROE-PROJECT/monroe-experiment-core)
2. ```apt install ./monroe-tap-agent*.deb```

## Endpoints : 

1. /api/v1.0/experiment/<string:schedid>/start', methods=['POST']
2. /api/v1.0/experiment/<string:schedid>/stop', methods=['POST']
3. /api/v1.0/experiment/<string:schedid>, methods=['GET']
4. /api/v1.0/experiment', methods=['GET']
5. /api/v1.0/experiment/<string:schedid>', methods=['POST']
6. /api/v1.0/experiment/<string:schedid>', methods=['PUT']
7. /api/v1.0/experiment/<string:schedid>', methods=['DELETE']
8. /api/v1.0/experiment/<string:schedid>/results', methods=['GET']

### Actions
1. Will deploy and start a experiment, eg:
    * ```curl --insecure -H 'x-api-key: $3cr3t_Pa$$w0rd!' -d '{ "script": "jonakarl/nodetest"}' -H "Content-Type: application/json" -X POST https://<URL>:8080/api/v1.0/experiment/test1/start```
2. Will stop (ie delete a experiment) and retrive the results (as a zip file), eg: 
    * ```curl --insecure -H 'x-api-key: $3cr3t_Pa$$w0rd!' -X POST https://<URL>:8080/api/v1.0/experiment/test1/stop -o test1.zip```
3. Will retrive status of a given experiment, eg: 
    * ```curl https://<URL>:8080/api/v1.0/experiment/test1```
        * HTTP_200_OK --- experiment is still running 
        * HTTP_428_PRECONDITION_REQUIRED --- experiment is deployed but not running (either stopped or has not started yet)
        * HTTP_404_NOT_FOUND --- experiment is not deplyed (ie does not exist)
4. Will return currently running and deployed experiments, eg: 
    * ```curl https://<URL>:8080/api/v1.0/experiment```
5. Deploys a experiment, eg: 
    *  ```curl --insecure -H 'x-api-key: $3cr3t_Pa$$w0rd!' -d '{ "script": "jonakarl/nodetest"}' -H "Content-Type: application/json" -X POST https://<URL>:8080/api/v1.0/experiment/test1```
6. Starts a experiment, eg: 
    * ```curl --insecure -H 'x-api-key: $3cr3t_Pa$$w0rd!' -X PUT https://<URL>:8080/api/v1.0/experiment/test1```
7. Will stop aka delete a experiment, eg: 
    * ```curl --insecure -H 'x-api-key: $3cr3t_Pa$$w0rd!' -X DELETE https://<URL>:8080/api/v1.0/experiment/test1```
8. Will sync and retrive the current results of a experiment (as a zip file), eg: 
    * ```curl --insecure -H 'x-api-key: $3cr3t_Pa$$w0rd!' https://<URL>:8080/api/v1.0/experiment/test1/results -o test1.zip```
