# monroe-experiment-core
Experimental MONROE as a package (MaaP).
This is currently the Monore DEV branch.
 
## Rationale 
The rationale behind this repo/package is to allow monroe (with minimal dependencys) to be installed on a fresh Debian installation.

## How to install
1. Intstall a fresh debian stretch (with defaults) 
2. Install docker: ```curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh```
3. Install monroe-experiment-core
    1. Get circle and table-allocator-* deb packages (build or get from a running monroe node)
    2. ```apt install ./circle_1.1.2-deb8u3_all.deb ./table-allocator-client_0.1.2-deb8u-20170831x1107-65b66b_amd64.deb ./table-allocator-server_0.1.2-deb8u-20170831x1107-65b66b_amd64.deb ./monroe-experiment.deb jq ssh libuv1 libjson-c3 libjq1 libonig4 dnsutils```

### Run a experiment and check so it works
1. create a test.conf in /experimenst/user/
2. execute ```container-deploy.sh test``` # check so all files/mounts has happened
3. execute ```container-start.sh test``` # check if soime out put was produced
4. execute ```monroe-sync-experiments``` # check so it a container.log was produced and that files are synched)
5. execute ```container-stop.sh test``` # checks so the .stopped file was produced
6. execute ```monroe-sync-experiments``` # and see that all fiels are synched and that the experiement is cleanued up.
