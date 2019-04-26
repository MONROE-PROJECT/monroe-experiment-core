# monroe-experiment-core
Experimental MONROE as a package (MaaP).
This is currently the Monroe DEV branch.
 
## Rationale 
The rationale behind this repo/package is to allow monroe (with minimal dependencys) to be installed on a fresh Debian installation.

## Howto Build (need to have docker,bash and internet connection)
1. clone this repo 
2. cd monroe-experiment-core 
3. ./build.sh core 


## Howto install
1. Install a fresh debian stretch (with defaults) 
2. Install docker: ```curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh```
3. Install monroe-experiment-core  
    1. Get circle and table-allocator-* deb packages (build or get from a running monroe node)
    2. ```apt install ./circle_1.1.2-deb8u3_all.deb ./table-allocator-client_0.1.2-deb8u-20170831x1107-65b66b_amd64.deb ./table-allocator-server_0.1.2-deb8u-20170831x1107-65b66b_amd64.deb ./monroe-experiment.deb jq ssh libuv1 libjson-c3 libjq1 libonig4 dnsutils```

### Run a experiment and check so it works
1. create a test.conf in /experimenst/user/
2. execute ```container-deploy.sh test``` # check so all files/mounts has happened
3. execute ```container-start.sh test``` # check if some output was produced
4. execute ```monroe-sync-experiments``` # check so a container.log was produced and that files are synched
5. execute ```container-stop.sh test``` # checks so the .stopped file was produced
6. execute ```monroe-sync-experiments``` # check that all files are synched and that the experiement is cleanued up.

# TODO (both near time and moonshots)
* See what is requried to make it install on Ubuntu 18.04 LTS (do we depend on ifupdown anywhere in the code)
* Remove/rework dependency on circle and table-allocator (ie make optional or remove binary components)
* Create a full plugin system with hooks into the main scripts (container-deploy/start/stop)
* Re-integerate current functionality as plugins (vm and neat support)
* Rework the experiment state checking code (ie stopped/running/deployed etc) to make it more robust
